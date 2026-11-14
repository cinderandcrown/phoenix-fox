// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// Spotify Web API client (search, play, skip, library, now playing).
/// Playback control requires an active Spotify Connect device (usually the phone Spotify app).
@MainActor
final class SpotifyWebAPI {
    static let shared = SpotifyWebAPI()
    private let base = URL(string: "https://api.spotify.com/v1")!

    func searchTracks(query: String, limit: Int = 5) async throws -> [(uri: String, name: String, artist: String)] {
        var comps = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "type", value: "track"),
            .init(name: "limit", value: String(limit)),
        ]
        let json = try await get(comps.url!)
        let tracks = json["tracks"] as? [String: Any] ?? [:]
        let items = tracks["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
            let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            return (uri, name, artists.joined(separator: ", "))
        }
    }

    func searchPlaylists(query: String, limit: Int = 5) async throws -> [(uri: String, name: String)] {
        var comps = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "type", value: "playlist"),
            .init(name: "limit", value: String(limit)),
        ]
        let json = try await get(comps.url!)
        let playlists = json["playlists"] as? [String: Any] ?? [:]
        let items = playlists["items"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let uri = item["uri"] as? String, let name = item["name"] as? String else { return nil }
            return (uri, name)
        }
    }

    func play(uris: [String]? = nil, contextURI: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let uris { body["uris"] = uris }
        if let contextURI { body["context_uri"] = contextURI }
        try await put(base.appendingPathComponent("me/player/play"), body: body.isEmpty ? nil : body)
    }

    func pause() async throws {
        try await put(base.appendingPathComponent("me/player/pause"), body: nil)
    }

    func next() async throws {
        try await post(base.appendingPathComponent("me/player/next"))
    }

    func previous() async throws {
        try await post(base.appendingPathComponent("me/player/previous"))
    }

    func setVolume(_ percent: Int) async throws {
        let clamped = min(100, max(0, percent))
        var comps = URLComponents(url: base.appendingPathComponent("me/player/volume"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "volume_percent", value: String(clamped))]
        try await put(comps.url!, body: nil)
    }

    func currentlyPlaying() async throws -> NowPlayingInfo? {
        let json = try await get(base.appendingPathComponent("me/player/currently-playing"))
        guard let item = json["item"] as? [String: Any],
              let title = item["name"] as? String else { return nil }
        let artists = (item["artists"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let album = (item["album"] as? [String: Any])?["name"] as? String
        let uri = item["uri"] as? String
        return NowPlayingInfo(title: title, artist: artists.joined(separator: ", "), album: album, uri: uri)
    }

    func saveTrack(uri: String) async throws {
        let id = uri.split(separator: ":").last.map(String.init) ?? uri
        var comps = URLComponents(url: base.appendingPathComponent("me/tracks"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "ids", value: id)]
        try await put(comps.url!, body: nil)
    }

    // MARK: - HTTP

    private func get(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await SpotifyPKCEAuth.shared.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(response, data: data)
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func put(_ url: URL, body: [String: Any]?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(try await SpotifyPKCEAuth.shared.validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(response, data: data)
    }

    private func post(_ url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(try await SpotifyPKCEAuth.shared.validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(response, data: data)
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) || http.statusCode == 204 { return }
        if http.statusCode == 401 || http.statusCode == 403 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.lowercased().contains("premium") {
                throw MusicProviderError.needsPremium("Spotify")
            }
            throw MusicProviderError.notAuthorized
        }
        if http.statusCode == 404 {
            throw MusicProviderError.unavailable("Open Spotify on this iPhone and start playing once, then try again.")
        }
        throw MusicProviderError.unavailable("Spotify returned \(http.statusCode).")
    }
}
