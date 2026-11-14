// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

struct NowPlayingInfo: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String?
    var uri: String?

    var spoken: String {
        if artist.isEmpty { return title }
        return "\(title) by \(artist)"
    }
}

enum MusicProviderID: String, Codable, CaseIterable, Identifiable, Sendable {
    case spotify
    case appleMusic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .appleMusic: return "Apple Music"
        }
    }
}

enum MusicProviderError: Equatable, LocalizedError, Sendable {
    case notConfigured
    case notInstalled(String)
    case needsPremium(String)
    case notAuthorized
    case nothingPlaying
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Music is not set up. Open Settings, Music, and connect a service."
        case .notInstalled(let name): return "\(name) is not installed on this iPhone."
        case .needsPremium(let name): return "\(name) Premium is needed for that on the glasses."
        case .notAuthorized: return "Music access was denied. You can allow it in Settings."
        case .nothingPlaying: return "Nothing is playing."
        case .unavailable(let why): return why
        }
    }
}

/// One music backend (Spotify App Remote / Web API, or Apple Music / MusicKit).
@MainActor
protocol MusicProvider: AnyObject {
    var id: MusicProviderID { get }
    var isConfigured: Bool { get }
    var isPlaying: Bool { get }

    func connect() async throws
    func play(query: String?) async throws
    func playPlaylist(named name: String) async throws
    func pause() async throws
    func resume() async throws
    func skip() async throws
    func previous() async throws
    func setVolume(delta: Int) async throws
    func saveCurrent() async throws
    func nowPlaying() async throws -> NowPlayingInfo
}
