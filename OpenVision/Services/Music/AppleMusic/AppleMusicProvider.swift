// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import AVFoundation
import Foundation
import MediaPlayer
import MusicKit

@MainActor
final class AppleMusicProvider: MusicProvider {
    static let shared = AppleMusicProvider()

    let id: MusicProviderID = .appleMusic
    private let player = ApplicationMusicPlayer.shared
    private(set) var isPlaying = false

    var isConfigured: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    func connect() async throws {
        let status = await MusicAuthorization.request()
        guard status == .authorized else { throw MusicProviderError.notAuthorized }
        configureNowPlayingCommands()
    }

    func play(query: String?) async throws {
        try await connect()
        if let query, !query.isEmpty {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 5
            let response = try await request.response()
            guard let song = response.songs.first else {
                throw MusicProviderError.unavailable("I couldn't find \(query) on Apple Music.")
            }
            player.queue = [song]
        }
        try await player.play()
        isPlaying = true
        publishNowPlaying()
    }

    func playPlaylist(named name: String) async throws {
        try await connect()
        var request = MusicCatalogSearchRequest(term: name, types: [Playlist.self])
        request.limit = 5
        let response = try await request.response()
        guard let playlist = response.playlists.first else {
            throw MusicProviderError.unavailable("I couldn't find a playlist called \(name).")
        }
        let detailed = try await playlist.with([.tracks])
        guard let tracks = detailed.tracks, !tracks.isEmpty else {
            throw MusicProviderError.unavailable("That playlist has no songs I can play.")
        }
        player.queue = ApplicationMusicPlayer.Queue(for: tracks)
        try await player.play()
        isPlaying = true
        publishNowPlaying()
    }

    func pause() async throws {
        player.pause()
        isPlaying = false
    }

    func resume() async throws {
        try await player.play()
        isPlaying = true
    }

    func skip() async throws {
        try await player.skipToNextEntry()
        publishNowPlaying()
    }

    func previous() async throws {
        try await player.skipToPreviousEntry()
        publishNowPlaying()
    }

    func setVolume(delta: Int) async throws {
        // MusicKit has no per-app volume API; AVAudioSession outputVolume is read-only.
        _ = delta
        throw MusicProviderError.unavailable("Use the phone volume buttons for Apple Music volume.")
    }

    func saveCurrent() async throws {
        try await connect()
        let info = try await nowPlaying()
        var request = MusicCatalogSearchRequest(term: "\(info.title) \(info.artist)", types: [Song.self])
        request.limit = 1
        let response = try await request.response()
        guard let song = response.songs.first else {
            throw MusicProviderError.unavailable("I couldn't match the current song in Apple Music.")
        }
        try await MusicLibrary.shared.add(song)
    }

    func nowPlaying() async throws -> NowPlayingInfo {
        if let entry = player.queue.currentEntry {
            let title = entry.title ?? "Unknown"
            return NowPlayingInfo(title: title, artist: "", album: nil, uri: nil)
        }
        // Fall back to system Now Playing (works when another app is playing too).
        if let map = MPNowPlayingInfoCenter.default().nowPlayingInfo,
           let title = map[MPMediaItemPropertyTitle] as? String {
            let artist = map[MPMediaItemPropertyArtist] as? String ?? ""
            let album = map[MPMediaItemPropertyAlbumTitle] as? String
            return NowPlayingInfo(title: title, artist: artist, album: album, uri: nil)
        }
        throw MusicProviderError.nothingPlaying
    }

    private func publishNowPlaying() {
        Task {
            guard let info = try? await nowPlaying() else { return }
            var map: [String: Any] = [
                MPMediaItemPropertyTitle: info.title,
                MPMediaItemPropertyArtist: info.artist,
            ]
            if let album = info.album { map[MPMediaItemPropertyAlbumTitle] = album }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = map
        }
    }

    private func configureNowPlayingCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.skip() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in try? await self?.previous() }
            return .success
        }
    }
}
