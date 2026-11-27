// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// First run, as a plan: five steps, what each says, and what happens when one is skipped.
//
// The rules are here so they can be tested. A step can always be skipped, because someone
// whose glasses are still in the post should be able to look around. Nothing is asked for
// before its reason has been given in plain words. The views in OnboardingView draw this.

import Foundation

enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case glasses
    case permissions
    case assistants
    case ready

    /// The step saved under `raw`. A number from a newer or older version lands on a real step.
    static func restored(_ raw: Int) -> OnboardingStep {
        OnboardingStep(rawValue: min(max(raw, 0), allCases.count - 1)) ?? .welcome
    }

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }

    /// "Step 2 of 5". Said by VoiceOver when a step appears, and shown above the title.
    var progress: String { "Step \(rawValue + 1) of \(Self.allCases.count)" }

    var symbol: String {
        switch self {
        case .welcome: return "flame.fill"
        case .glasses: return "eyeglasses"
        case .permissions: return "hand.raised.fill"
        case .assistants: return "person.3.fill"
        case .ready: return "checkmark.seal.fill"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Meet Phoenix"
        case .glasses: return "Connect your glasses"
        case .permissions: return "Let Phoenix hear you"
        case .assistants: return "Connect your assistants"
        case .ready: return "You're set"
        }
    }

    /// One short paragraph under the title.
    var summary: String {
        switch self {
        case .welcome:
            return "Phoenix Fox puts your assistants in your glasses. Say “Hey Phoenix”, ask for what you need, and hear the answer. Setting up takes about a minute."
        case .glasses:
            return "Before you tap Open Meta AI, pair your glasses in the Meta AI app, update Meta AI and your glasses, and turn on Developer Mode. The steps are below. Then Meta AI asks you to allow Phoenix Fox and brings you back here."
        case .permissions:
            return "Phoenix Fox asks for three things now. Anything else, such as your location, is asked for the first time you use a feature that needs it."
        case .assistants:
            return "If you run your own assistants behind a relay, enter its details and they will answer you. You can also add a Grok key for fast looks. If you skip both, Phoenix answers on this phone."
        case .ready:
            return "Put your glasses on and say the wake word."
        }
    }

    /// What to do before the step's main button, in order. Only the glasses step has any:
    /// Meta AI refuses to connect until these are done, and says only "Internal error".
    var preparation: [String] {
        self == .glasses ? GlassesPreparation.steps : []
    }

    /// The glasses step's main button.
    static func glassesButton(connected: Bool, stall: RegistrationStall?) -> String {
        if connected { return "Continue" }
        return stall?.canRetry == true ? "Try again" : "Open Meta AI"
    }

    /// What the step promises about privacy, where it has something to promise.
    var promise: String? {
        switch self {
        case .glasses:
            return "The camera is used only when you ask Phoenix to look. The capture light on the glasses is on whenever the camera is. Phoenix Fox cannot turn that light off."
        case .assistants:
            return "The relay token is kept in this phone's Keychain."
        case .welcome, .permissions, .ready:
            return nil
        }
    }

    /// The title of the step's skip button. The first and last steps have nothing to skip.
    var skipTitle: String? {
        switch self {
        case .welcome, .ready: return nil
        case .glasses: return "I'll do this later"
        case .permissions: return "Not now"
        case .assistants: return "Skip, I don't have a relay"
        }
    }
}

// MARK: - Permissions

/// What the wearer has said to one of the system's permission questions.
enum PermissionAnswer: Equatable, Sendable {
    case notAsked
    case allowed
    /// Only the Settings app can change this now.
    case denied
}

/// The permissions asked for during first run. Each says why in plain words first.
enum OnboardingPermission: String, CaseIterable, Sendable {
    case microphone
    case speech
    case notifications

    var symbol: String {
        switch self {
        case .microphone: return "mic.fill"
        case .speech: return "waveform"
        case .notifications: return "bell.badge.fill"
        }
    }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .speech: return "Speech recognition"
        case .notifications: return "Notifications"
        }
    }

    /// Why Phoenix Fox asks, in one or two sentences a person would say.
    var reason: String {
        switch self {
        case .microphone:
            return "So Phoenix can hear you through your glasses. Without it, voice does not work."
        case .speech:
            return "So Phoenix can hear its wake word and turn what you say into text."
        case .notifications:
            return "So an assistant can tell you when a task is finished. You can leave this off."
        }
    }

    /// Voice does not work without this one.
    var isNeededForVoice: Bool { self != .notifications }

    /// The row's button, or nil when there is nothing left to do.
    func buttonTitle(_ answer: PermissionAnswer) -> String? {
        switch answer {
        case .notAsked: return "Allow"
        case .allowed: return nil
        case .denied: return "Open Settings"
        }
    }

    /// The line under the reason once the wearer has answered.
    func status(_ answer: PermissionAnswer) -> String? {
        switch answer {
        case .notAsked: return nil
        case .allowed: return "Allowed"
        case .denied: return "Turned off. You can turn it on in the Settings app."
        }
    }

    /// What VoiceOver says for the whole row.
    func spoken(_ answer: PermissionAnswer) -> String {
        [title, status(answer), reason].compactMap { $0 }.joined(separator: ". ")
    }
}

// MARK: - Who answers

/// Which AI answers when first run ends.
enum StartingBrain: Equatable, Sendable {
    /// The relay is set up, so the wearer's own assistants answer.
    case assistants
    /// The wearer already chose another AI and it works. Leave it.
    case keepCurrent
    /// Nothing is set up. The AI built into the phone answers, so there is a working start.
    case onDevice
    /// Nothing is set up and this phone has no built-in AI. The last step says so.
    case none

    /// - Parameters:
    ///   - relayReady: a relay address and token are saved.
    ///   - currentIsAssistants: the chosen AI is "Your assistants".
    ///   - currentReady: the chosen AI has what it needs to answer.
    ///   - onDeviceReady: the phone's built-in AI is available.
    static func choose(relayReady: Bool, currentIsAssistants: Bool, currentReady: Bool, onDeviceReady: Bool) -> StartingBrain {
        if relayReady && currentIsAssistants { return .assistants }
        if !currentIsAssistants && currentReady { return .keepCurrent }
        if relayReady { return .assistants }
        return onDeviceReady ? .onDevice : .none
    }
}

/// The checklist on the last step: what is set up and what was left for later.
struct OnboardingSummary: Equatable, Sendable {
    struct Line: Equatable, Sendable, Identifiable {
        let id: String
        let done: Bool
        let text: String
    }

    let lines: [Line]
    /// What to do first, in the wearer's own wake word.
    let tryThis: String
    /// Jarvis can hold a conversation as things stand.
    let canTalk: Bool

    init(glassesConnected: Bool, microphone: PermissionAnswer, speech: PermissionAnswer, brain: StartingBrain, wakeWord: String) {
        let hears = microphone == .allowed && speech == .allowed
        var lines = [
            Line(id: "glasses", done: glassesConnected, text: glassesConnected
                 ? "Glasses connected."
                 : "Glasses not connected yet. Until then, Phoenix uses this phone's microphone."),
            Line(id: "voice", done: hears, text: hears
                 ? "Phoenix can hear you."
                 : "Phoenix cannot hear you yet. Allow the microphone and speech recognition in Settings."),
        ]
        switch brain {
        case .assistants:
            lines.append(Line(id: "brain", done: true, text: "Your assistants are connected."))
        case .keepCurrent:
            lines.append(Line(id: "brain", done: true, text: "Your chosen AI is ready."))
        case .onDevice:
            lines.append(Line(id: "brain", done: true, text: "Phoenix answers on this phone. Connect your assistants any time in Settings."))
        case .none:
            lines.append(Line(id: "brain", done: false, text: "Nothing is set to answer yet. Choose an AI in Settings."))
        }
        self.lines = lines
        canTalk = hears && brain != .none
        if !canTalk {
            tryThis = "Finish the steps above in Settings, then say “\(wakeWord)”."
        } else if brain == .assistants {
            tryThis = "Say “\(wakeWord), what should I do next?”"
        } else {
            tryThis = "Say “\(wakeWord), what can you do?”"
        }
    }
}
