// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Spotify Web API OAuth with PKCE only — no client secret in the app.
// Verified against Spotify iOS SDK auth docs (PKCE default when tokenSwapURL is nil)
// and https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
// (fetched Nov 2026).

import Foundation
import AuthenticationServices

struct SpotifyTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var scopes: String

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

@MainActor
final class SpotifyPKCEAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyPKCEAuth()

    private let storeKey = "ov.spotify.tokens"
    private var session: ASWebAuthenticationSession?

    /// Redirect must match the Spotify Dashboard allowlist and Info.plist URL scheme.
    static let redirectURI = "phoenixfox://spotify-callback"
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    static let scopes = [
        "app-remote-control",
        "user-modify-playback-state",
        "user-read-playback-state",
        "user-read-currently-playing",
        "user-library-modify",
        "user-library-read",
        "playlist-read-private",
        "playlist-read-collaborative",
    ].joined(separator: " ")

    var clientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var hasClientID: Bool {
        let id = clientID
        return !id.isEmpty && !id.hasPrefix("$(")
    }

    var tokens: SpotifyTokens? {
        get {
            guard let data = SpotifyTokenKeychain.data(account: storeKey) else { return nil }
            return try? JSONDecoder().decode(SpotifyTokens.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                SpotifyTokenKeychain.set(data, account: storeKey)
            } else {
                SpotifyTokenKeychain.delete(account: storeKey)
            }
        }
    }

    var isSignedIn: Bool { tokens != nil }

    func signOut() { tokens = nil }

    func validAccessToken() async throws -> String {
        guard hasClientID else { throw MusicProviderError.notConfigured }
        if let tokens, !tokens.isExpired { return tokens.accessToken }
        if let tokens, let refresh = tokens.refreshToken {
            let refreshed = try await refreshAccessToken(refresh)
            self.tokens = refreshed
            return refreshed.accessToken
        }
        let fresh = try await authorize()
        self.tokens = fresh
        return fresh.accessToken
    }

    func authorize() async throws -> SpotifyTokens {
        guard hasClientID else { throw MusicProviderError.notConfigured }
        let verifier = PKCE.randomString()
        let state = PKCE.randomString(byteCount: 16)
        var comps = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "state", value: state),
        ]
        guard let url = comps.url else { throw MusicProviderError.unavailable("Could not start Spotify sign-in.") }

        let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "phoenixfox") { callback, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let callback {
                    cont.resume(returning: callback)
                } else {
                    cont.resume(throwing: MusicProviderError.notAuthorized)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: MusicProviderError.unavailable("Could not open Spotify sign-in."))
            }
        }

        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw MusicProviderError.notAuthorized
        }
        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == state else { throw MusicProviderError.notAuthorized }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw MusicProviderError.notAuthorized
        }
        return try await exchange(code: code, verifier: verifier)
    }

    private func exchange(code: String, verifier: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicProviderError.unavailable("Spotify token exchange failed.")
        }
        return try decodeTokens(data)
    }

    private func refreshAccessToken(_ refresh: String) async throws -> SpotifyTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID,
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MusicProviderError.unavailable("Spotify token refresh failed.")
        }
        var tokens = try decodeTokens(data)
        if tokens.refreshToken == nil { tokens.refreshToken = refresh }
        return tokens
    }

    private func decodeTokens(_ data: Data) throws -> SpotifyTokens {
        struct Payload: Decodable {
            var access_token: String
            var refresh_token: String?
            var expires_in: Double
            var scope: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return SpotifyTokens(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(payload.expires_in),
            scopes: payload.scope ?? ""
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

/// Keychain helpers for Spotify tokens only (account-scoped).
enum SpotifyTokenKeychain {
    static func data(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func set(_ data: Data, account: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
