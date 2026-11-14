// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Where spoken answers go, and which Bluetooth link the glasses use.
//
// Meta's mic and speaker guide (verified against DAT 1.0.1 README + our GLASSES_SDK notes):
// - HFP (mic + low-latency voice) and A2DP (higher-quality speaker) cannot run at the
//   same time on the glasses. The app picks one link mode at a time.
// - The HFP route must be fully settled before the camera stream starts, or audio can
//   fail with no error.
// - The glasses mic on HFP is mono 16 kHz, tuned to the wearer's voice.
//
// These rules are plain data so they can be tested without AVFoundation.

import Foundation

/// A port iOS reports on the current audio route, reduced to what this app needs.
enum AudioPortKind: String, Equatable, Sendable {
    case bluetoothHFP
    case bluetoothA2DP
    case builtInSpeaker
    case builtInReceiver
    case builtInMic
    case headphones
    case other

    var isBluetooth: Bool { self == .bluetoothHFP || self == .bluetoothA2DP }
}

struct AudioPort: Equatable, Sendable {
    var kind: AudioPortKind
    var name: String
}

struct AudioRouteSnapshot: Equatable, Sendable {
    var inputs: [AudioPort]
    var outputs: [AudioPort]
    var availableInputs: [AudioPort]

    var hasBluetoothOutput: Bool { outputs.contains { $0.kind.isBluetooth } }
    var hasBluetoothHFPInput: Bool {
        availableInputs.contains { $0.kind == .bluetoothHFP }
            || inputs.contains { $0.kind == .bluetoothHFP }
    }
    var hasHFPOutput: Bool { outputs.contains { $0.kind == .bluetoothHFP } }
    var hasA2DPOutput: Bool { outputs.contains { $0.kind == .bluetoothA2DP } }

    var bluetoothOutputName: String? {
        outputs.first { $0.kind.isBluetooth }?.name
    }

    var description: String {
        let inNames = inputs.map(\.name).joined(separator: ", ")
        let outNames = outputs.map(\.name).joined(separator: ", ")
        return "Input: \(inNames.isEmpty ? "none" : inNames), Output: \(outNames.isEmpty ? "none" : outNames)"
    }
}

/// Where the wearer wants spoken answers to go.
enum SpeakerPreference: String, Codable, CaseIterable, Sendable {
    case auto
    case glasses
    case phone

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .glasses: return "Glasses"
        case .phone: return "iPhone speaker"
        }
    }
}

/// The Bluetooth link mode for the glasses. HFP and A2DP are mutually exclusive.
enum GlassesLinkMode: String, Equatable, Sendable {
    /// Mic + short replies. Mono 16 kHz, tuned to the wearer. Required while listening.
    case hfpConversation
    /// Higher-quality speaker only. No glasses mic. For long playback when not listening.
    case a2dpPlayback
    /// No glasses Bluetooth audio; phone mic and loud speaker.
    case phone

    var title: String {
        switch self {
        case .hfpConversation: return "Glasses voice link (HFP)"
        case .a2dpPlayback: return "Glasses speaker (A2DP)"
        case .phone: return "iPhone"
        }
    }

    /// HFP allows the mic; A2DP does not. Never both.
    var allowsHFP: Bool { self == .hfpConversation }
    var allowsA2DP: Bool { self == .a2dpPlayback }
    var usesGlassesMic: Bool { self == .hfpConversation }
}

enum AudioDestination: Equatable, Sendable {
    case glasses(name: String, link: GlassesLinkMode)
    case phoneSpeaker

    /// Route label only — Home prefixes with "Speaking through" once.
    var title: String {
        switch self {
        case .glasses(let name, let link):
            let short = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let who = short.isEmpty ? "glasses" : short
            switch link {
            case .hfpConversation: return "\(who) (voice link)"
            case .a2dpPlayback: return "\(who) (speaker)"
            case .phone: return who
            }
        case .phoneSpeaker:
            return "iPhone speaker"
        }
    }

    var isGlasses: Bool {
        if case .glasses = self { return true }
        return false
    }
}

struct AudioSessionPlan: Equatable, Sendable {
    var link: GlassesLinkMode
    var preferHFPMic: Bool
    var defaultToSpeaker: Bool
    var clearSpeakerOverride: Bool
    var forceSpeakerOverride: Bool
    var allowHFP: Bool
    var allowA2DP: Bool
    var destination: AudioDestination
    /// Seconds to wait after activating HFP before the camera may start.
    var hfpSettleSeconds: Double
}

enum AudioRoutePolicy {
    /// How long HFP needs after activation before the camera stream may start.
    static let hfpSettleSeconds = 0.7

    static func linkMode(
        snapshot: AudioRouteSnapshot,
        preference: SpeakerPreference,
        preferGlassesMic: Bool,
        cameraStreaming: Bool,
        listening: Bool,
        longPlayback: Bool
    ) -> GlassesLinkMode {
        if preference == .phone { return .phone }
        let glassesPresent = snapshot.hasBluetoothHFPInput || snapshot.hasBluetoothOutput
        if preference == .glasses, !glassesPresent { return .phone }
        if !glassesPresent { return .phone }

        // Camera saturates the link: drop HFP mic while streaming. Prefer A2DP for
        // playback-only, or phone if the wearer needs to keep listening on the phone mic.
        if cameraStreaming {
            if longPlayback, snapshot.hasA2DPOutput || snapshot.hasBluetoothOutput {
                return .a2dpPlayback
            }
            // Keep answers on glasses when possible via A2DP; mic stays on the phone.
            return snapshot.hasBluetoothOutput || snapshot.hasBluetoothHFPInput ? .a2dpPlayback : .phone
        }

        // Listening or a short conversational turn: HFP only (mic + reply). Never A2DP here.
        if listening || preferGlassesMic {
            return snapshot.hasBluetoothHFPInput ? .hfpConversation : .phone
        }

        // Long TTS with no mic needed: A2DP for quality.
        if longPlayback {
            return .a2dpPlayback
        }

        return snapshot.hasBluetoothHFPInput ? .hfpConversation : .phone
    }

    static func destination(snapshot: AudioRouteSnapshot, link: GlassesLinkMode) -> AudioDestination {
        switch link {
        case .phone:
            return .phoneSpeaker
        case .hfpConversation, .a2dpPlayback:
            let name = snapshot.bluetoothOutputName
                ?? snapshot.availableInputs.first { $0.kind == .bluetoothHFP }?.name
                ?? "glasses"
            return .glasses(name: name, link: link)
        }
    }

    static func plan(
        snapshot: AudioRouteSnapshot,
        preference: SpeakerPreference,
        preferGlassesMic: Bool,
        cameraStreaming: Bool,
        listening: Bool = true,
        longPlayback: Bool = false
    ) -> AudioSessionPlan {
        let link = linkMode(
            snapshot: snapshot,
            preference: preference,
            preferGlassesMic: preferGlassesMic,
            cameraStreaming: cameraStreaming,
            listening: listening,
            longPlayback: longPlayback
        )
        let whereTo = destination(snapshot: snapshot, link: link)
        let glassesOut = whereTo.isGlasses
        return AudioSessionPlan(
            link: link,
            preferHFPMic: link.usesGlassesMic && preferGlassesMic && snapshot.hasBluetoothHFPInput,
            defaultToSpeaker: !glassesOut,
            clearSpeakerOverride: glassesOut,
            forceSpeakerOverride: !glassesOut,
            allowHFP: link.allowsHFP,
            allowA2DP: link.allowsA2DP,
            destination: whereTo,
            hfpSettleSeconds: link == .hfpConversation ? hfpSettleSeconds : 0
        )
    }

    /// Whether the camera may start given the current link. HFP must be settled first.
    static func cameraMayStart(link: GlassesLinkMode, hfpSettled: Bool) -> Bool {
        switch link {
        case .hfpConversation: return hfpSettled
        case .a2dpPlayback, .phone: return true
        }
    }
}
