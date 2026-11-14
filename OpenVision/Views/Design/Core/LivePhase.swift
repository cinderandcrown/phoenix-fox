// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// What Jarvis is doing right now, in words a person can read at a glance.
//
// The voice pipeline has many internal states. The home screen shows one of a handful of
// phases, each with a word, a line of help, a symbol, and a mood for the orb. Whether the
// camera is on is shown beside the phase and never hidden by it. This file decides which;
// the views only draw the answer.

import Foundation

/// The voice pipeline's state, as the home screen needs it.
enum VoiceActivity: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case thinking
    case usingTool
    case speaking
    case liveVideo
}

/// Everything the phase is decided from.
struct LiveSignals: Equatable, Sendable {
    var activity: VoiceActivity = .idle
    /// The wake-word listener has loaded and is running.
    var voiceReady = true
    var wakeWordOn = true
    var wakeWord = "Jarvis"
    /// The glasses camera is on, so the capture light is on.
    var cameraOn = false
    /// The assistant that has been asked and has not answered yet.
    var askedAssistant: String?
    /// What a tool is doing, when one is running.
    var tool: String?
}

enum LivePhase: Equatable, Sendable {
    /// The voice model is still loading.
    case gettingReady
    /// Waiting for the wake word or a tap.
    case ready
    case connecting
    case listening
    /// Thinking about something the camera is showing.
    case looking
    case thinking
    /// An assistant has the question.
    case asking(String)
    /// A tool is running.
    case working(String?)
    case replying
    case liveVideo

    init(_ signals: LiveSignals) {
        switch signals.activity {
        case .liveVideo:
            self = .liveVideo
        case .speaking:
            self = .replying
        case .listening:
            self = .listening
        case .connecting:
            self = .connecting
        case .usingTool:
            self = signals.cameraOn ? .looking : .working(Self.cleaned(signals.tool))
        case .thinking:
            if let name = Self.cleaned(signals.askedAssistant) {
                self = .asking(name)
            } else {
                self = signals.cameraOn ? .looking : .thinking
            }
        case .idle:
            self = signals.voiceReady || !signals.wakeWordOn ? .ready : .gettingReady
        }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// One or two words, set large under the orb.
    var title: String {
        switch self {
        case .gettingReady: return "Getting ready"
        case .ready: return "Ready"
        case .connecting: return "Waking up"
        case .listening: return "Listening"
        case .looking: return "Looking"
        case .thinking: return "Thinking"
        case .asking(let name): return "Asking \(name)"
        case .working: return "Working"
        case .replying: return "Replying"
        case .liveVideo: return "Live video"
        }
    }

    /// One short line under the title: what to do, or what is happening.
    func hint(_ signals: LiveSignals) -> String {
        switch self {
        case .gettingReady:
            return "Loading the voice on this phone."
        case .ready:
            return signals.wakeWordOn ? "Say “\(signals.wakeWord)” or tap." : "Tap to talk."
        case .connecting:
            return "One moment."
        case .listening:
            return "Go ahead."
        case .looking:
            return "Through your glasses."
        case .thinking:
            return "One moment."
        case .asking:
            return "Waiting for the answer."
        case .working(let tool):
            return tool ?? "One moment."
        case .replying:
            return "Say “\(signals.wakeWord), stop” or tap."
        case .liveVideo:
            return "Say “stop video” to end."
        }
    }

    /// The SF Symbol that goes with the title.
    var symbol: String {
        switch self {
        case .gettingReady, .connecting: return "hourglass"
        case .ready: return "flame.fill"
        case .listening: return "waveform"
        case .looking: return "eye.fill"
        case .thinking: return "ellipsis"
        case .asking: return "paperplane.fill"
        case .working: return "gearshape.fill"
        case .replying: return "speaker.wave.2.fill"
        case .liveVideo: return "video.fill"
        }
    }

    /// How the orb moves.
    var mood: OrbMood {
        switch self {
        case .gettingReady, .ready: return .resting
        case .listening: return .listening
        case .connecting, .looking, .thinking, .asking, .working: return .thinking
        case .replying, .liveVideo: return .replying
        }
    }

    /// What a tap on the orb does in this phase.
    var tap: StageTap {
        switch self {
        case .replying: return .stopTalking
        case .gettingReady, .ready: return .start
        case .connecting, .listening, .looking, .thinking, .asking, .working, .liveVideo: return .end
        }
    }

    /// Something is in progress, so the screen should show it moving.
    var isBusy: Bool {
        switch self {
        case .gettingReady, .connecting, .looking, .thinking, .asking, .working: return true
        case .ready, .listening, .replying, .liveVideo: return false
        }
    }
}

enum OrbMood: String, CaseIterable, Sendable {
    case resting
    case listening
    case thinking
    case replying
}

enum StageTap: Equatable, Sendable {
    /// Start a conversation.
    case start
    /// Stop the answer and listen again.
    case stopTalking
    /// End the conversation.
    case end

    /// What VoiceOver says the tap will do.
    var accessibilityHint: String {
        switch self {
        case .start: return "Starts a conversation."
        case .stopTalking: return "Stops the answer and listens again."
        case .end: return "Ends the conversation."
        }
    }
}

/// What the stage says to VoiceOver, as one element.
struct StageDescription: Equatable, Sendable {
    let label: String
    let value: String
    let hint: String

    init(phase: LivePhase, signals: LiveSignals) {
        label = "Jarvis"
        var parts = [phase.title, phase.hint(signals)]
        if signals.cameraOn {
            parts.append("The camera on your glasses is on.")
        }
        value = parts.joined(separator: ". ").replacingOccurrences(of: ".. ", with: ". ")
        hint = phase.tap.accessibilityHint
    }
}

// MARK: - The glasses

/// What the chip at the top of the home screen says about the glasses.
enum GlassesStatus: Equatable, Sendable {
    /// Phoenix Fox has not been connected to the glasses in the Meta AI app.
    case notConnected
    /// Connected, and no pair is in reach right now: in the case, off, or out of range.
    case away
    case ready
    /// The camera is on.
    case cameraOn

    /// - Parameter linkConnected: DAT `LinkState.connected` — devices listed ≠ reachable.
    init(registered: Bool, devicesInReach: Int, cameraOn: Bool, linkConnected: Bool = false) {
        if !registered {
            self = .notConnected
        } else if cameraOn {
            self = .cameraOn
        } else if linkConnected, devicesInReach > 0 {
            self = .ready
        } else {
            // Registered but DAT link not up, or no device listed yet.
            self = .away
        }
    }

    var title: String {
        switch self {
        case .notConnected: return "Connect glasses"
        case .away: return "Glasses away"
        case .ready: return "Glasses ready"
        case .cameraOn: return "Camera on"
        }
    }

    /// What VoiceOver says. The chip is a button that opens the glasses settings.
    var spoken: String {
        switch self {
        case .notConnected: return "Glasses are not connected."
        case .away: return "Glasses are registered but not linked for this app yet. Open Glasses check and run the CameraAccess probe, or toggle Bluetooth."
        case .ready: return "Glasses are connected and ready."
        case .cameraOn: return "The camera on your glasses is on."
        }
    }
}

// MARK: - Haptics

/// A moment worth feeling. The view plays each with the system's own feedback.
enum HapticCue: String, CaseIterable, Sendable {
    /// Jarvis started listening.
    case listening
    /// Jarvis heard the request and took it.
    case heard
    /// The answer started.
    case replying
    /// The glasses camera came on.
    case cameraOn
    /// An assistant answered while Jarvis was quiet.
    case arrived
    /// An urgent alert.
    case urgent
    /// Something went wrong.
    case trouble

    /// The cue for the phase changing, if the change is one a hand should feel.
    ///
    /// Only the three beats of a turn get one: listening, heard, replying. Going back to
    /// rest is silent, and so is anything that repeats.
    static func cue(from old: LivePhase, to new: LivePhase) -> HapticCue? {
        guard old != new else { return nil }
        switch new {
        case .listening:
            // After an answer the microphone reopens by itself. That is not a new moment.
            return old == .replying ? nil : .listening
        case .looking, .thinking, .asking, .working:
            return old == .listening ? .heard : nil
        case .replying:
            return .replying
        case .gettingReady, .ready, .connecting, .liveVideo:
            return nil
        }
    }

    /// The cue for the camera going on or off. Coming on is felt. Going off is not.
    static func cue(cameraWasOn: Bool, cameraIsOn: Bool) -> HapticCue? {
        !cameraWasOn && cameraIsOn ? .cameraOn : nil
    }
}
