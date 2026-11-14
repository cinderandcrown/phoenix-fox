// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Hands-free music on the glasses: provider + A2DP/HFP session choreography.
//
// Verified in code against AudioRoutePolicy / DAT exclusivity (HFP ≠ A2DP).
// On-glasses soak still required: stereo must return after a voice command.

import AVFoundation
import Foundation

@MainActor
final class MusicCoordinator: ObservableObject {
    static let shared = MusicCoordinator()

    @Published private(set) var phase: MusicAudioPhase = .idle
    @Published private(set) var lastSpoken: String?

    private var musicWasPlayingBeforeCapture = false

    var activeProvider: MusicProvider {
        switch SettingsManager.shared.settings.musicProvider {
        case .spotify: return SpotifyMusicProvider.shared
        case .appleMusic: return AppleMusicProvider.shared
        }
    }

    var isMusicPlaying: Bool {
        SpotifyMusicProvider.shared.isPlaying || AppleMusicProvider.shared.isPlaying
    }

    /// Handles a parsed music command. Returns spoken feedback for the wearer.
    func handle(_ command: MusicCommand) async -> String {
        do {
            switch command {
            case .identify:
                // Prefer Shazam on-device; fall back to provider now-playing.
                if let shazam = try? await ShazamIdentify.shared.identify() {
                    return "That's \(shazam.spoken)."
                }
                let info = try await activeProvider.nowPlaying()
                return "That's \(info.spoken)."

            case .nowPlaying:
                let info = try await activeProvider.nowPlaying()
                return info.spoken

            case .play(let query):
                try await withMusicPlayback {
                    try await activeProvider.play(query: query)
                }
                if let query, !query.isEmpty {
                    return "Playing \(query)."
                }
                return "Playing."

            case .playPlaylist(let name):
                try await withMusicPlayback {
                    try await activeProvider.playPlaylist(named: name)
                }
                return "Playing \(name)."

            case .pause:
                try await activeProvider.pause()
                await restoreA2DPIfNeeded()
                return "Paused."

            case .resume:
                try await withMusicPlayback {
                    try await activeProvider.resume()
                }
                return "Resuming."

            case .skip:
                try await activeProvider.skip()
                await restoreA2DPIfNeeded()
                return "Skipping."

            case .previous:
                try await activeProvider.previous()
                await restoreA2DPIfNeeded()
                return "Going back."

            case .volumeUp:
                try await activeProvider.setVolume(delta: 1)
                return "Turning it up."

            case .volumeDown:
                try await activeProvider.setVolume(delta: -1)
                return "Turning it down."

            case .save:
                try await activeProvider.saveCurrent()
                return "Saved to your library."
            }
        } catch let error as MusicProviderError {
            return error.errorDescription ?? "Music isn't available."
        } catch {
            return error.localizedDescription
        }
    }

    /// Call when the wake word fires while music may be on A2DP.
    func beginVoiceCapture() {
        musicWasPlayingBeforeCapture = isMusicPlaying
        guard musicWasPlayingBeforeCapture else { return }
        phase = .voiceCaptureHFP
        applyPhase(.voiceCaptureHFP, duck: true)
    }

    /// Call when command capture ends (before or after handling).
    func endVoiceCapture() {
        let next = MusicSessionPolicy.phaseAfterCommand(musicWasPlaying: musicWasPlayingBeforeCapture || isMusicPlaying)
        phase = next
        applyPhase(next, duck: false)
        musicWasPlayingBeforeCapture = false
    }

    /// Duck music under assistant TTS, then restore A2DP.
    func beginAssistantSpeech() {
        guard isMusicPlaying || musicWasPlayingBeforeCapture else { return }
        phase = .assistantDucked
        applyPhase(.assistantDucked, duck: true)
    }

    func endAssistantSpeech() {
        let next = isMusicPlaying ? MusicAudioPhase.musicA2DP : .idle
        phase = next
        applyPhase(next, duck: false)
    }

    // MARK: - Session

    private func withMusicPlayback(_ work: () async throws -> Void) async throws {
        try await work()
        phase = .musicA2DP
        applyPhase(.musicA2DP, duck: false)
    }

    private func restoreA2DPIfNeeded() async {
        guard isMusicPlaying else { return }
        phase = .musicA2DP
        applyPhase(.musicA2DP, duck: false)
    }

    private func applyPhase(_ phase: MusicAudioPhase, duck: Bool) {
        let settings = SettingsManager.shared.settings
        let flags = MusicSessionPolicy.routeFlags(phase: phase)

        do {
            // Music on A2DP: release our HFP hold so Spotify/Apple Music can keep stereo.
            // Activating playAndRecord with HFP while music plays is what drops glasses to call quality.
            if phase == .musicA2DP || phase == .idle {
                try? AudioSessionManager.shared.deactivate()
                // Re-apply A2DP-friendly playback route without the glasses mic.
                _ = try AudioSessionManager.shared.applyPreferredRoute(
                    preferGlassesMic: false,
                    speakerPreference: settings.speakerPreference,
                    cameraStreaming: GlassesManager.shared.isStreaming,
                    listening: false,
                    longPlayback: true
                )
                return
            }

            // Duck under TTS / mic without stopping the music app when possible.
            let session = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
            if duck || MusicSessionPolicy.shouldDuckOthers(phase: phase) {
                options.insert(.duckOthers)
            }
            let snap = AudioSessionManager.shared.snapshot()
            let plan = AudioRoutePolicy.plan(
                snapshot: snap,
                preference: settings.speakerPreference,
                preferGlassesMic: settings.preferGlassesMic && flags.listening,
                cameraStreaming: GlassesManager.shared.isStreaming,
                listening: flags.listening,
                longPlayback: flags.longPlayback
            )
            if plan.allowHFP { options.insert(.allowBluetoothHFP) }
            if plan.allowA2DP { options.insert(.allowBluetoothA2DP) }
            if plan.defaultToSpeaker { options.insert(.defaultToSpeaker) }
            // Exclusive: never request HFP and A2DP together (DAT constraint).
            if plan.allowHFP { options.remove(.allowBluetoothA2DP) }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setActive(true)

            _ = try AudioSessionManager.shared.applyPreferredRoute(
                preferGlassesMic: settings.preferGlassesMic && flags.listening,
                speakerPreference: settings.speakerPreference,
                cameraStreaming: GlassesManager.shared.isStreaming,
                listening: flags.listening,
                longPlayback: flags.longPlayback
            )
        } catch {
            print("[Music] Session apply failed: \(error.localizedDescription)")
        }
    }
}
