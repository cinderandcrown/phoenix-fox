// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Release-safe switches for items waiting on Nicholas's decision (legal review PR #18).
// Defaults are the conservative App Store option. Flip via UserDefaults without code surgery;
// owner builds may still override face recognition on through OwnerProfile when the flag allows.

import Foundation

enum PrivacyFeatureFlag: String, CaseIterable, Sendable {
    /// On-device face prints (`AccessFaces` / `FaceLedger`). Biometric risk.
    case faceRecognition
    /// ChatGPT Plus/Pro OAuth that reuses another app's client (guideline 5.2.2 risk).
    case chatGPTSubscriptionSignIn
    /// SuperGrok OAuth sign-in (same 5.2.2 class of risk).
    case superGrokSignIn
    /// Gemma 2 2B weights (license terms pending Nicholas).
    case gemma2_2B
    /// When true, Meta DAT telemetry is allowed (Info.plist OptOut must also be false).
    case metaDATTelemetry

    private static let prefix = "ov.privacy.flag."

    /// Conservative defaults for store / release builds.
    var defaultEnabled: Bool {
        switch self {
        case .faceRecognition:
            // Off in public (standard) builds. Owner builds keep it available for Nicholas.
            return BuildFlavor.current == .owner
        case .chatGPTSubscriptionSignIn, .superGrokSignIn, .gemma2_2B, .metaDATTelemetry:
            return false
        }
    }

    var defaultsKey: String { Self.prefix + rawValue }

    func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: defaultsKey) == nil { return defaultEnabled }
        return defaults.bool(forKey: defaultsKey)
    }

    func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: defaultsKey)
    }

    func resetToDefault(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    var displayName: String {
        switch self {
        case .faceRecognition: return "Face recognition"
        case .chatGPTSubscriptionSignIn: return "ChatGPT subscription sign-in"
        case .superGrokSignIn: return "SuperGrok sign-in"
        case .gemma2_2B: return "Gemma 2 2B model"
        case .metaDATTelemetry: return "Meta DAT telemetry"
        }
    }
}

enum PrivacyFeatureFlags {
    static var faceRecognition: Bool { PrivacyFeatureFlag.faceRecognition.isEnabled() }
    static var chatGPTSubscriptionSignIn: Bool { PrivacyFeatureFlag.chatGPTSubscriptionSignIn.isEnabled() }
    static var superGrokSignIn: Bool { PrivacyFeatureFlag.superGrokSignIn.isEnabled() }
    static var gemma2_2B: Bool { PrivacyFeatureFlag.gemma2_2B.isEnabled() }
    /// Info.plist currently ships OptOut=true. This flag documents intent; enabling telemetry
    /// also requires flipping `MWDAT > Analytics > OptOut` in a release build.
    static var metaDATTelemetry: Bool { PrivacyFeatureFlag.metaDATTelemetry.isEnabled() }
}
