// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// How music and the glasses voice link share the Bluetooth radio.
//
// DAT / Meta: HFP (mic + voice) and A2DP (stereo speaker) cannot run at once.
// When music is on A2DP, a wake-word capture must briefly take HFP (music ducks or
// pauses), then restore A2DP so stereo quality returns. Verified against
// AudioRoutePolicy + docs/GLASSES_SDK.md; on-glasses soak still required.

import Foundation

enum MusicAudioPhase: String, Equatable, Sendable {
    /// Stereo music on glasses A2DP; no mic on glasses.
    case musicA2DP
    /// Brief HFP for wake word / command (music may duck or pause).
    case voiceCaptureHFP
    /// Assistant speaking; duck music, prefer short HFP reply then restore.
    case assistantDucked
    /// Idle / phone.
    case idle
}

enum MusicSessionPolicy {
    /// Which glasses link to use for this phase.
    static func link(for phase: MusicAudioPhase, glassesPresent: Bool) -> GlassesLinkMode {
        guard glassesPresent else { return .phone }
        switch phase {
        case .musicA2DP: return .a2dpPlayback
        case .voiceCaptureHFP, .assistantDucked: return .hfpConversation
        case .idle: return .phone
        }
    }

    /// After a voice command while music was playing, always restore A2DP.
    static func phaseAfterCommand(musicWasPlaying: Bool) -> MusicAudioPhase {
        musicWasPlaying ? .musicA2DP : .idle
    }

    /// Whether the session should request `.duckOthers` so Spotify/Apple Music softens under TTS.
    static func shouldDuckOthers(phase: MusicAudioPhase) -> Bool {
        phase == .assistantDucked || phase == .voiceCaptureHFP
    }

    /// Arguments for AudioRoutePolicy.plan while coordinating music.
    static func routeFlags(phase: MusicAudioPhase) -> (listening: Bool, longPlayback: Bool) {
        switch phase {
        case .musicA2DP: return (listening: false, longPlayback: true)
        case .voiceCaptureHFP: return (listening: true, longPlayback: false)
        case .assistantDucked: return (listening: false, longPlayback: false)
        case .idle: return (listening: true, longPlayback: false)
        }
    }
}
