// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Builds the diagnostics object posted with beta feedback.
// Always redacted. Media stays out unless the tester opts in (and even then only
// metadata is included here — raw frames are never attached from the ring).

import Foundation

enum DiagnosticsSnapshot {
    /// Collects a JSON-ready diagnostics dictionary for `POST /feedback`.
    @MainActor
    static func build(
        settings: AppSettings,
        glasses: GlassesManager,
        includeMedia: Bool
    ) -> [String: Any] {
        var glassesState: [String: Any] = [
            "registered": glasses.isRegistered,
            "streaming": glasses.isStreaming,
            "paused": glasses.isPaused,
            "pending_registration": glasses.pendingRegistration != nil,
            "connected_count": glasses.connectedDeviceCount,
        ]
        if let profile = glasses.streamProfile {
            glassesState["stream_profile"] = String(describing: profile)
        }
        if let error = glasses.errorMessage, !error.isEmpty {
            glassesState["error"] = LogRedactor.redact(error)
        }
        if let failure = WearablesSDK.failure {
            glassesState["sdk_failure"] = LogRedactor.redact(failure)
        }

        var provider = ProviderDiagnostics.shared.snapshot()
        if provider["backend"] as? String == "" {
            provider["backend"] = settings.aiBackend.rawValue
        }
        provider["backend_display"] = settings.aiBackend.displayName
        switch settings.aiBackend {
        case .grok, .claude, .openAI:
            provider["catalog_model"] = InstantModels.id(for: settings.aiBackend, settings: settings)
        default:
            break
        }

        let audio = AudioSessionManager.shared
        let payload: [String: Any] = [
            "app_version": Config.appVersion,
            "build": Config.buildNumber,
            "build_flavor": BuildFlavor.current.label,
            "system": [
                "ios": ProcessInfo.processInfo.operatingSystemVersionString,
                "low_power": ProcessInfo.processInfo.isLowPowerModeEnabled,
            ],
            "audio": [
                "mode": String(describing: audio.currentMode),
                "route": audio.currentRouteDescription,
                "hfp_active": audio.isBluetoothHFPActive,
                "built_in_mic": audio.isUsingBuiltInMic,
                "history": AudioRouteHistory.shared.snapshot(),
            ],
            "glasses": glassesState,
            "provider": provider,
            "logs": DiagnosticsRingBuffer.shared.snapshot(),
            "include_media": includeMedia,
            "media_note": includeMedia
                ? "Tester opted in; attach screenshots via TestFlight if needed. Raw audio/images are not uploaded from the log ring."
                : "Media omitted",
        ]
        return LogRedactor.redactJSON(payload) as? [String: Any] ?? payload
    }
}
