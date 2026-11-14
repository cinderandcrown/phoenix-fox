// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The plans, and the three things a plan can unlock.
//
// Everything that runs on the phone is free, and so is the whole accessibility suite. A plan
// is only ever needed for a model in the cloud or for more than one assistant. The reasons
// and the arithmetic are in docs/BUSINESS_MODEL.md.

import Foundation

enum Plan: String, CaseIterable, Sendable {
    case free
    case ownAI = "ownai"
    case includedAI = "includedai"
    case botTeam = "botteam"

    /// Each plan holds everything in the plans below it.
    var rank: Int {
        switch self {
        case .free: return 0
        case .ownAI: return 1
        case .includedAI: return 2
        case .botTeam: return 3
        }
    }

    var name: String {
        switch self {
        case .free: return "Free"
        case .ownAI: return "Own AI"
        case .includedAI: return "Included AI"
        case .botTeam: return "Bot Team"
        }
    }

    /// What the Plan screen lists under the name.
    var includes: [String] {
        switch self {
        case .free:
            return [
                "The whole accessibility suite: reading, money, colors, labels, Guide mode, walking directions, captions, sound alerts, and task steps.",
                "The wake word, and questions answered by the model on this phone.",
                "The emergency contact call.",
            ]
        case .ownAI:
            return [
                "Everything in Free.",
                "Questions and looks answered by Grok, Claude, OpenAI, or Gemini with your own key. The maker of the model bills you for what you use.",
                "Live voice and video with your own key.",
                "One assistant of your own, over your own relay.",
            ]
        case .includedAI:
            return [
                "Everything in Own AI.",
                "Questions and looks answered with no key to set up, up to a monthly allowance.",
            ]
        case .botTeam:
            return [
                "Everything in the plans below it.",
                "More than one assistant: ask each one by name, and call all hands.",
            ]
        }
    }
}

extension Plan: Comparable {
    static func < (left: Plan, right: Plan) -> Bool { left.rank < right.rank }
}

/// Something a free plan does not cover.
enum PaidFeature: CaseIterable, Sendable {
    /// A model in the cloud reached with the wearer's own key, or one assistant over the
    /// wearer's own relay. Somebody else bills the wearer for the use.
    case ownKeyAI
    /// A model in the cloud that Cinder & Crown pays for.
    case includedAI
    /// More than one assistant.
    case botTeam

    /// The cheapest plan that covers it.
    var plan: Plan {
        switch self {
        case .ownKeyAI: return .ownAI
        case .includedAI: return .includedAI
        case .botTeam: return .botTeam
        }
    }

    /// What Jarvis says when the plan does not cover it. It always says what still works.
    var refusal: String {
        switch self {
        case .ownKeyAI:
            return "A model in the cloud needs the Own AI plan. On the phone, open Settings, then Plan. Reading, Guide mode, and the model on the phone still work."
        case .includedAI:
            return "Answers with no key of your own need the Included AI plan. On the phone, open Settings, then Plan. Reading, Guide mode, and the model on the phone still work."
        case .botTeam:
            return "More than one assistant needs the Bot Team plan. On the phone, open Settings, then Plan. Your first assistant still works."
        }
    }
}

extension AIBackendType {
    /// What a turn answered by this brain needs from the plan. The brains on the phone need nothing.
    var paidFeature: PaidFeature? {
        switch self {
        case .appleFoundation, .localGemma:
            return nil
        case .openClaw, .geminiLive, .openAI, .grok, .hermes, .claude, .ownAssistant:
            return .ownKeyAI
        }
    }
}
