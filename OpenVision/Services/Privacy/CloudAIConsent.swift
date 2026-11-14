// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Guideline 5.1.2(i): before any cloud AI provider receives prompts, photos, or memories,
// the wearer must explicitly agree on screen. Per-provider timestamps; revocable in Settings.
// Pure logic so Linux unit tests can run.

import Foundation

/// Cloud destinations that need an on-screen consent before personal data is sent.
enum CloudAIProvider: String, CaseIterable, Identifiable, Sendable {
    case grok
    case openAI
    case claude
    case gemini
    case hermes
    case openClaw
    case ownAssistant

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grok: return "Grok (xAI)"
        case .openAI: return "ChatGPT / OpenAI"
        case .claude: return "Claude (Anthropic)"
        case .gemini: return "Gemini (Google)"
        case .hermes: return "Hermes"
        case .openClaw: return "OpenClaw"
        case .ownAssistant: return "Your own assistant (relay)"
        }
    }

    var shortName: String {
        switch self {
        case .grok: return "xAI"
        case .openAI: return "OpenAI"
        case .claude: return "Anthropic"
        case .gemini: return "Google"
        case .hermes: return "Hermes"
        case .openClaw: return "OpenClaw"
        case .ownAssistant: return "your relay"
        }
    }

    var privacyPolicyURL: URL? {
        switch self {
        case .grok: return URL(string: "https://x.ai/legal/privacy-policy")
        case .openAI: return URL(string: "https://openai.com/policies/privacy-policy")
        case .claude: return URL(string: "https://www.anthropic.com/legal/privacy")
        case .gemini: return URL(string: "https://policies.google.com/privacy")
        case .hermes, .openClaw, .ownAssistant: return nil
        }
    }

    static func from(backend: AIBackendType) -> CloudAIProvider? {
        switch backend {
        case .appleFoundation, .localGemma: return nil
        case .grok: return .grok
        case .openAI: return .openAI
        case .claude: return .claude
        case .geminiLive: return .gemini
        case .hermes: return .hermes
        case .openClaw: return .openClaw
        case .ownAssistant: return .ownAssistant
        }
    }
}

enum CloudAIConsent {
    /// Legacy single-consent key (migrated to per-provider on first read).
    static let legacyDefaultsKey = "ov.cloudAIDataConsentAcceptedAt"
    static let defaultsPrefix = "ov.cloudAI.consent."

    static func defaultsKey(for provider: CloudAIProvider) -> String {
        defaultsPrefix + provider.rawValue
    }

    static func isAccepted(_ provider: CloudAIProvider, defaults: UserDefaults = .standard) -> Bool {
        migrateLegacyIfNeeded(defaults: defaults)
        return defaults.object(forKey: defaultsKey(for: provider)) != nil
    }

    static func acceptedAt(_ provider: CloudAIProvider, defaults: UserDefaults = .standard) -> Date? {
        migrateLegacyIfNeeded(defaults: defaults)
        guard let raw = defaults.object(forKey: defaultsKey(for: provider)) as? Double else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    /// True when any cloud provider has been accepted (Settings summary).
    static func isAccepted(defaults: UserDefaults = .standard) -> Bool {
        migrateLegacyIfNeeded(defaults: defaults)
        return CloudAIProvider.allCases.contains { isAccepted($0, defaults: defaults) }
    }

    static func acceptedAt(defaults: UserDefaults = .standard) -> Date? {
        migrateLegacyIfNeeded(defaults: defaults)
        return CloudAIProvider.allCases.compactMap { acceptedAt($0, defaults: defaults) }.min()
    }

    static func accept(_ provider: CloudAIProvider, now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now.timeIntervalSince1970, forKey: defaultsKey(for: provider))
    }

    /// Accept every listed cloud provider (first-run sheet that covers the chosen backend).
    static func accept(_ providers: [CloudAIProvider], now: Date = Date(), defaults: UserDefaults = .standard) {
        for provider in providers { accept(provider, now: now, defaults: defaults) }
    }

    static func withdraw(_ provider: CloudAIProvider, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey(for: provider))
    }

    static func withdraw(defaults: UserDefaults = .standard) {
        for provider in CloudAIProvider.allCases {
            withdraw(provider, defaults: defaults)
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }

    /// Whether a cloud (off-device) brain may send a request right now.
    static func allowsCloudSend(backend: AIBackendType, defaults: UserDefaults = .standard) -> Bool {
        guard let provider = CloudAIProvider.from(backend: backend) else { return true }
        return isAccepted(provider, defaults: defaults)
    }

    static func promptTitle(for provider: CloudAIProvider) -> String {
        "Send to \(provider.displayName)?"
    }

    static func promptBody(for provider: CloudAIProvider, liveMode: Bool = false, cloudVoice: Bool = false) -> String {
        var bullets = [
            "• what you say, as text, and recent conversation",
            "• pictures from your glasses, when you ask Jarvis to look",
            "• your saved memories and custom instructions",
        ]
        if liveMode {
            bullets.append("• your voice and camera video, streamed for as long as live mode is on")
        }
        if cloudVoice {
            bullets.append("• Jarvis's replies, to turn them into speech")
        }
        if provider == .ownAssistant {
            return """
            Phoenix Fox sends what you say, recent conversation, and pictures you include to the relay you configured, and from there to the assistants it's set up for. Whoever runs that relay is responsible for it.

            Your face data and medication log are never sent.

            You can change this in Settings → Privacy & Data.
            """
        }
        return """
        To answer you, Phoenix Fox sends \(provider.shortName):
        \(bullets.joined(separator: "\n"))

        \(provider.shortName) handles this under its own privacy policy and your account. Phoenix Fox doesn't keep a copy on any server. Your face data and medication log are never sent.

        You can change this in Settings → Privacy & Data.
        """
    }

    /// Shared key-entry disclosure under API key fields.
    static let keyEntryDisclosure =
        "Requests (and photos you attach) are sent to this provider under their privacy policy. The key stays in this phone's Keychain and is never logged."

    // MARK: - Legacy migration

    private static func migrateLegacyIfNeeded(defaults: UserDefaults) {
        guard let raw = defaults.object(forKey: legacyDefaultsKey) as? Double else { return }
        for provider in CloudAIProvider.allCases {
            let key = defaultsKey(for: provider)
            if defaults.object(forKey: key) == nil {
                defaults.set(raw, forKey: key)
            }
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
