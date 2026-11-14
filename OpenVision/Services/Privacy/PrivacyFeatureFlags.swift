// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Release switches from Nicholas's privacy decisions (Nov 2026).
// Meta DAT telemetry: always OFF. ChatGPT/SuperGrok OAuth: owner+flag only.
// Face recognition: shipped in all builds, default OFF until wearer opt-in + attorney sign-off.

import Foundation

enum PrivacyFeatureFlag: String, CaseIterable, Sendable {
    /// Feature available in the binary. Settings stay default-OFF until wearer CUBI/BIPA opt-in.
    case faceRecognition
    /// ChatGPT Plus/Pro OAuth (5.2.2). Store/release builds never show it.
    case chatGPTSubscriptionSignIn
    /// SuperGrok OAuth (5.2.2). Store/release builds never show it.
    case superGrokSignIn
    /// Gemma 2 2B weights (license pending).
    case gemma2_2B
    /// Meta DAT SDK telemetry. Locked OFF in every build (Info.plist OptOut=true).
    case metaDATTelemetry

    private static let prefix = "ov.privacy.flag."

    /// Flags an owner may toggle in Settings → Privacy & Data.
    static var ownerToggleable: [PrivacyFeatureFlag] {
        [.faceRecognition, .chatGPTSubscriptionSignIn, .superGrokSignIn, .gemma2_2B]
    }

    var defaultEnabled: Bool {
        switch self {
        case .faceRecognition:
            // Shipped for all builds; the feature toggle in Accessibility stays OFF by default.
            return true
        case .chatGPTSubscriptionSignIn, .superGrokSignIn, .gemma2_2B, .metaDATTelemetry:
            return false
        }
    }

    var defaultsKey: String { Self.prefix + rawValue }

    func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        switch self {
        case .metaDATTelemetry:
            // Locked off in all builds (documented MWDAT Analytics OptOut).
            return false
        case .chatGPTSubscriptionSignIn, .superGrokSignIn:
            // Removed from store/release; owner/debug may enable via flag.
            guard BuildFlavor.current == .owner else { return false }
            if defaults.object(forKey: defaultsKey) == nil { return defaultEnabled }
            return defaults.bool(forKey: defaultsKey)
        case .faceRecognition, .gemma2_2B:
            if defaults.object(forKey: defaultsKey) == nil { return defaultEnabled }
            return defaults.bool(forKey: defaultsKey)
        }
    }

    func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) {
        switch self {
        case .metaDATTelemetry:
            return // cannot enable
        case .chatGPTSubscriptionSignIn, .superGrokSignIn:
            guard BuildFlavor.current == .owner else { return }
            defaults.set(on, forKey: defaultsKey)
        case .faceRecognition, .gemma2_2B:
            defaults.set(on, forKey: defaultsKey)
        }
    }

    func resetToDefault(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    var displayName: String {
        switch self {
        case .faceRecognition: return "Face recognition (feature available)"
        case .chatGPTSubscriptionSignIn: return "ChatGPT subscription sign-in"
        case .superGrokSignIn: return "SuperGrok sign-in"
        case .gemma2_2B: return "Gemma 2 2B model"
        case .metaDATTelemetry: return "Meta DAT telemetry (locked off)"
        }
    }
}

enum PrivacyFeatureFlags {
    static var faceRecognition: Bool { PrivacyFeatureFlag.faceRecognition.isEnabled() }
    static var chatGPTSubscriptionSignIn: Bool { PrivacyFeatureFlag.chatGPTSubscriptionSignIn.isEnabled() }
    static var superGrokSignIn: Bool { PrivacyFeatureFlag.superGrokSignIn.isEnabled() }
    static var gemma2_2B: Bool { PrivacyFeatureFlag.gemma2_2B.isEnabled() }
    /// Always false. Info.plist `MWDAT > Analytics > OptOut` is true.
    static var metaDATTelemetry: Bool { false }
}
