// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import UIKit
import UserNotifications

/// Permission for alerts from the assistants, and registration with Apple's push service.
///
/// The app does not ask at launch. It asks when the wearer turns alerts on, which is right
/// after they connect the relay the alerts come from. At launch it only renews the
/// registration if permission was already given.
@MainActor
enum PushAlerts {
    enum Status: Equatable {
        /// The wearer has not been asked.
        case notAsked
        case on
        /// Turned off. Only the Settings app can turn it back on.
        case off

        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notAsked
            case .authorized, .provisional, .ephemeral: self = .on
            case .denied: self = .off
            @unknown default: self = .off
            }
        }

        /// One line for the Settings row.
        var line: String {
            switch self {
            case .notAsked: return "Off. Turn on to hear from your assistants when the app is closed."
            case .on: return "On."
            case .off: return "Off in iOS Settings."
            }
        }
    }

    static func status() async -> Status {
        Status(await authorization())
    }

    /// Registers with Apple when alerts are allowed. Shows the system question first only
    /// when `askIfNeeded` is true and the wearer has never answered it.
    @discardableResult
    static func refresh(askIfNeeded: Bool) async -> Status {
        var current = await status()
        if current == .notAsked, askIfNeeded {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            current = granted ? .on : .off
        }
        if current == .on {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return current
    }

    private nonisolated static func authorization() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }
}
