// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Guideline 5.1.2(i): before any cloud AI provider receives prompts or photos, the wearer
// must explicitly agree that that data leaves the phone. Pure logic so Linux tests can run.

import Foundation

enum CloudAIConsent {
    /// UserDefaults key for the acceptance timestamp (timeIntervalSince1970).
    static let defaultsKey = "ov.cloudAIDataConsentAcceptedAt"

    /// True when the wearer has accepted cloud AI data sharing on this phone.
    static func isAccepted(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) != nil
    }

    static func acceptedAt(defaults: UserDefaults = .standard) -> Date? {
        guard let raw = defaults.object(forKey: defaultsKey) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    static func accept(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: defaultsKey)
    }

    static func withdraw(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// Whether a cloud (off-device) brain may send a request right now.
    static func allowsCloudSend(backend: AIBackendType, defaults: UserDefaults = .standard) -> Bool {
        switch backend {
        case .appleFoundation, .localGemma:
            return true
        case .grok, .claude, .openAI, .geminiLive, .ownAssistant, .hermes, .openClaw:
            return isAccepted(defaults: defaults)
        }
    }

    static let promptTitle = "Cloud AI data sharing"

    static let promptBody = """
    When you use a cloud brain (Grok, Claude, ChatGPT, Gemini, Hermes, or your own relay), \
    what you say and any photo you attach leave this iPhone and go to that service so it can answer. \
    Keys stay in the Keychain on this phone and are never logged. \
    Cinder & Crown does not receive your prompts.

    You can withdraw this anytime in Settings → Privacy & Data. On-device answers keep working without it.
    """

    static let keyEntryDisclosure = \
        "Requests (and photos you attach) are sent to this provider under their privacy policy. The key stays in this phone's Keychain and is never logged."
}
