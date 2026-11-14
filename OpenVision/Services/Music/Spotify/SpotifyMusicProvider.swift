// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Spotify via Web API (PKCE, no client secret) + App Remote when SpotifyiOS is linked.
// App Remote requires the Spotify app and typically Premium for full control.
// Developer Mode: up to 5 allowlisted users; Extended Quota required for public release
// (see docs/SDK_NOTES.md). Verified Nov 2026 against Spotify developer docs.

import Foundation
import UIKit

#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

@MainActor
final class SpotifyMusicProvider: MusicProvider {
    static let shared = SpotifyMusicProvider()

    let id: MusicProviderID = .spotify
    private(set) var isPlaying = false
    private var lastVolume = 50

#if canImport(SpotifyiOS)
    private var appRemote: SPTAppRemote?
#endif

    var isConfigured: Bool {
        SpotifyPKCEAuth.shared.hasClientID && SpotifyPKCEAuth.shared.isSignedIn
    }

    var isSpotifyInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "spotify:")!)
    }

    func connect() async throws {
        guard SpotifyPKCEAuth.shared.hasClientID else { throw MusicProviderError.notConfigured }
        _ = try await SpotifyPKCEAuth.shared.validAccessToken()
        try await connectAppRemoteIfAvailable()
    }

    func play(query: String?) async throws {
        try await ensureReady()
        if let query, !query.isEmpty {
            let hits = try await SpotifyWebAPI.shared.searchTracks(query: query)
            guard let first = hits.first else {
                throw MusicProviderError.unavailable("I couldn't find \(query) on Spotify.")
            }
            try await playURI(first.uri)
            isPlaying = true
            return
        }
        try await SpotifyWebAPI.shared.play()
        isPlaying = true
    }

    func playPlaylist(named name: String) async throws {
        try await ensureReady()
        let lists = try await SpotifyWebAPI.shared.searchPlaylists(query: name)
        guard let match = lists.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) ?? lists.first else {
            throw MusicProviderError.unavailable("I couldn't find a playlist called \(name).")
        }
        try await SpotifyWebAPI.shared.play(contextURI: match.uri)
        isPlaying = true
    }

    func pause() async throws {
        try await ensureReady()
        if !(await pauseViaAppRemote()) {
            try await SpotifyWebAPI.shared.pause()
        }
        isPlaying = false
    }

    func resume() async throws {
        try await ensureReady()
        try await SpotifyWebAPI.shared.play()
        isPlaying = true
    }

    func skip() async throws {
        try await ensureReady()
        if !(await skipViaAppRemote()) {
            try await SpotifyWebAPI.shared.next()
        }
    }

    func previous() async throws {
        try await ensureReady()
        try await SpotifyWebAPI.shared.previous()
    }

    func setVolume(delta: Int) async throws {
        try await ensureReady()
        lastVolume = min(100, max(0, lastVolume + delta * 10))
        try await SpotifyWebAPI.shared.setVolume(lastVolume)
    }

    func saveCurrent() async throws {
        try await ensureReady()
        guard let info = try await SpotifyWebAPI.shared.currentlyPlaying(), let uri = info.uri else {
            throw MusicProviderError.nothingPlaying
        }
        try await SpotifyWebAPI.shared.saveTrack(uri: uri)
    }

    func nowPlaying() async throws -> NowPlayingInfo {
        try await ensureReady()
        guard let info = try await SpotifyWebAPI.shared.currentlyPlaying() else {
            throw MusicProviderError.nothingPlaying
        }
        return info
    }

    // MARK: - Internals

    private func ensureReady() async throws {
        if !isSpotifyInstalled {
            throw MusicProviderError.notInstalled("Spotify")
        }
        try await connect()
    }

    private func playURI(_ uri: String) async throws {
        if await playURIViaAppRemote(uri) { return }
        try await SpotifyWebAPI.shared.play(uris: [uri])
    }

    private func connectAppRemoteIfAvailable() async throws {
#if canImport(SpotifyiOS)
        let token = try await SpotifyPKCEAuth.shared.validAccessToken()
        let config = SPTConfiguration(
            clientID: SpotifyPKCEAuth.shared.clientID,
            redirectURL: URL(string: SpotifyPKCEAuth.redirectURI)!
        )
        let remote = SPTAppRemote(configuration: config, logLevel: .info)
        remote.connectionParameters.accessToken = token
        appRemote = remote
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            remote.connect()
            // Connection callbacks are async; give the radio a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { cont.resume() }
        }
#else
        // Web API path only until SpotifyiOS.xcframework is linked (see SDK_NOTES.md).
#endif
    }

    private func playURIViaAppRemote(_ uri: String) async -> Bool {
#if canImport(SpotifyiOS)
        guard let remote = appRemote, remote.isConnected else { return false }
        return await withCheckedContinuation { cont in
            remote.playerAPI?.play(uri) { _, error in
                cont.resume(returning: error == nil)
            }
        }
#else
        return false
#endif
    }

    private func pauseViaAppRemote() async -> Bool {
#if canImport(SpotifyiOS)
        guard let remote = appRemote, remote.isConnected else { return false }
        return await withCheckedContinuation { cont in
            remote.playerAPI?.pause { _, error in
                cont.resume(returning: error == nil)
            }
        }
#else
        return false
#endif
    }

    private func skipViaAppRemote() async -> Bool {
#if canImport(SpotifyiOS)
        guard let remote = appRemote, remote.isConnected else { return false }
        return await withCheckedContinuation { cont in
            remote.playerAPI?.skip(toNext: { _, error in
                cont.resume(returning: error == nil)
            })
        }
#else
        return false
#endif
    }
}
