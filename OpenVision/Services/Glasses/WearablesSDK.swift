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
@MainActor
enum WearablesSDK {
    private(set) static var interface: (any WearablesInterface)?

    /// Why the SDK did not start, in words for the Glasses screen.
    private(set) static var failure: String?

    /// Starts the SDK once. Safe to call again.
    static func start() {
        guard interface == nil else { return }
        do {
            try Wearables.configure()
            interface = Wearables.shared
            failure = nil
        } catch WearablesError.alreadyConfigured {
            interface = Wearables.shared
            failure = nil
        } catch {
            failure = message(for: error)
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
