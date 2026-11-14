// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation
import MWDATCore

/// The one place the app starts and reaches the Meta Wearables SDK.
///
/// `Wearables.shared` stops the app when it is read before `Wearables.configure()` has
/// succeeded. Everything else asks here instead and gets nil when the SDK is not running:
/// under unit tests, or when the Meta values in Info.plist are missing or wrong. The app
/// then still opens, and the Glasses screen says what is wrong.
///
/// Configure runs only after Bluetooth authorization is resolved (Meta DAT #116). Calling
/// configure first and granting Bluetooth later can leave `linkState` stuck at disconnected.
@MainActor
enum WearablesSDK {
    private(set) static var interface: (any WearablesInterface)?

    /// Why the SDK did not start, in words for the Glasses screen.
    private(set) static var failure: String?

    /// Bluetooth authorization recorded at configure time (for Copy log).
    private(set) static var bluetoothAtConfigure: String = "not-started"

    private static var didStartAfterBluetooth = false

    /// Resolves Bluetooth permission, then configures once. Safe to call again.
    static func startAfterBluetoothPermission() async {
        guard !didStartAfterBluetooth else { return }
        didStartAfterBluetooth = true
        let auth = await BluetoothPermission.ensureResolved()
        bluetoothAtConfigure = BluetoothPermission.label(for: auth)
        GlassesLink.shared.record(
            "Bluetooth auth before Wearables.configure: \(bluetoothAtConfigure)"
        )
        if auth == .denied || auth == .restricted {
            GlassesLink.shared.record(
                "Bluetooth not allowed — DAT link will stay disconnected until Settings → Phoenix Fox → Bluetooth is on, then force-quit and reopen."
            )
        }
        start()
        GlassesManager.shared.wearablesDidBecomeAvailable()
    }

    /// Starts the SDK once. Prefer `startAfterBluetoothPermission()` from the app.
    /// Safe to call again.
    static func start() {
        guard interface == nil else { return }
        do {
            try Wearables.configure()
            interface = Wearables.shared
            failure = nil
            GlassesLink.shared.record(
                "Wearables.configure OK. MetaAppID=\(DATEligibility.configuredMetaAppID) path=\(DATEligibility.datPathLabel) isDevMode=\(DATEligibility.isDevModeLabel(from: interface))"
            )
        } catch WearablesError.alreadyConfigured {
            interface = Wearables.shared
            failure = nil
            GlassesLink.shared.record(
                "Wearables already configured. MetaAppID=\(DATEligibility.configuredMetaAppID) path=\(DATEligibility.datPathLabel) isDevMode=\(DATEligibility.isDevModeLabel(from: interface))"
            )
        } catch {
            failure = message(for: error)
            GlassesLink.shared.record("Wearables.configure failed: \(failure ?? "unknown")")
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? WearablesError {
        case .configurationError?, .missingInfoDictionary?:
            return "This build is missing its Meta app settings, so it cannot connect to glasses. Install a newer build."
        case .missingBundleIdentifier?, .missingAppName?, .missingAppVersion?, .missingBuildNumber?:
            return "This build is missing app information the glasses need. Install a newer build."
        default:
            return "The glasses software did not start. Close Phoenix Fox and open it again."
        }
    }
}

/// Thrown when something needs the glasses and the SDK is not running.
struct GlassesUnavailable: LocalizedError {
    let reason: String

    @MainActor
    init() {
        reason = WearablesSDK.failure ?? "The glasses connection is not running."
    }

    var errorDescription: String? { reason }
}
