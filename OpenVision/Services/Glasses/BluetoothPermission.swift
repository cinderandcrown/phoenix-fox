// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Bluetooth must be authorized before Wearables.configure(). Meta confirmed on Android
// DAT #116: if initialize runs before the permission is granted, linkState can stay
// DISCONNECTED for the life of the process even after the user allows Bluetooth later.
// iOS has the same configure-once BLE path; prompt first, then configure.

import CoreBluetooth
import Foundation

@MainActor
enum BluetoothPermission {
    /// Resolves iOS Bluetooth authorization, prompting if needed. Does not throw.
    static func ensureResolved() async -> CBManagerAuthorization {
        let current = CBCentralManager.authorization
        switch current {
        case .allowedAlways, .denied, .restricted:
            return current
        case .notDetermined:
            return await Prompt.shared.waitForDecision()
        @unknown default:
            return current
        }
    }

    static func label(for authorization: CBManagerAuthorization) -> String {
        switch authorization {
        case .allowedAlways: return "allowed"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return String(describing: authorization)
        }
    }

    /// Holds a CBCentralManager long enough for the system prompt and first state callback.
    private final class Prompt: NSObject, CBCentralManagerDelegate {
        static let shared = Prompt()

        private var manager: CBCentralManager?
        private var waiting: [CheckedContinuation<CBManagerAuthorization, Never>] = []

        func waitForDecision() async -> CBManagerAuthorization {
            let already = CBCentralManager.authorization
            if already != .notDetermined { return already }
            return await withCheckedContinuation { continuation in
                waiting.append(continuation)
                if manager == nil {
                    manager = CBCentralManager(delegate: self, queue: .main)
                }
            }
        }

        func centralManagerDidUpdateState(_ central: CBCentralManager) {
            let auth = CBCentralManager.authorization
            guard auth != .notDetermined else { return }
            let pending = waiting
            waiting = []
            for continuation in pending {
                continuation.resume(returning: auth)
            }
        }
    }
}
