// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Snapshot of DAT identity / device eligibility fields for Glasses check Copy log.
// Cross-checks Meta Android DAT #116 (BT before configure), #177 (no re-register),
// #150 (BLE link while Meta AI holds glasses), and Wearables Developer Center
// release-channel vs MetaAppID 0 / Developer Mode.

import Foundation
import MWDATCore

@MainActor
enum DATEligibility {
    /// MetaAppID from Info.plist MWDAT (never the ClientToken).
    static var configuredMetaAppID: String {
        guard let mwdat = Bundle.main.object(forInfoDictionaryKey: "MWDAT") as? [String: Any],
              let id = mwdat["MetaAppID"] as? String,
              !id.isEmpty
        else { return "(missing)" }
        return id
    }

    /// True when MetaAppID is 0 / empty — Developer Mode path (no attestation).
    static var usesDeveloperModeAppID: Bool {
        let id = configuredMetaAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        return id == "0" || id == "$(META_APP_ID)" || id.isEmpty || id == "(missing)"
    }

    /// iOS WearablesInterface docs do not list `isDevMode` (Android does). Probe safely.
    /// Only call when `Wearables.configure()` has already succeeded (`wearables` non-nil).
    static func isDevModeLabel(from wearables: (any WearablesInterface)?) -> String {
        guard let wearables else { return "n/a (SDK not running)" }
        if let value = mirrorBool(wearables, key: "isDevMode") {
            return value ? "true" : "false"
        }
        // configure() already succeeded — shared is safe to read for reflection only.
        if let value = mirrorBool(Wearables.shared as Any, key: "isDevMode") {
            return value ? "true" : "false"
        }
        return "unavailable on iOS API (Android Wearables.isDevMode)"
    }

    /// One device line: name, link, compatibility, type, and any firmware string we can find.
    static func deviceLines(from wearables: any WearablesInterface) -> [String] {
        let ids = wearables.devices
        if ids.isEmpty { return ["devices: (none)"] }
        return ids.map { id in
            guard let device = wearables.deviceForIdentifier(id) else {
                return "device \(id): (deviceForIdentifier nil)"
            }
            let compat = String(describing: device.compatibility())
            let type = String(describing: device.deviceType())
            let firmware = firmwareLabel(for: device)
            return "\(device.nameOrId()) link=\(device.linkState) compat=\(compat) type=\(type) firmware=\(firmware)"
        }
    }

    static func snapshotLines(
        wearables: (any WearablesInterface)?,
        bluetooth: String,
        linkLabel: String,
        linkConnected: Bool,
        lastSDKError: String?
    ) -> [String] {
        var lines = [
            "MetaAppID: \(configuredMetaAppID)",
            "Dev-mode AppID path: \(usesDeveloperModeAppID ? "yes (0/empty)" : "no (real app id — needs release channel)")",
            "isDevMode: \(isDevModeLabel(from: wearables))",
            "Bluetooth auth: \(bluetooth)",
            "DAT link: \(linkLabel)",
            "Link ready: \(linkConnected ? "yes" : "no")",
            "Last SDK error: \(lastSDKError ?? "(none)")",
        ]
        if let wearables {
            lines.append("Registration: \(String(describing: wearables.registrationState))")
            lines.append(contentsOf: deviceLines(from: wearables))
        } else {
            lines.append("Registration: (SDK not running)")
        }
        return lines
    }

    private static func firmwareLabel(for device: Device) -> String {
        if let text = mirrorString(device, keys: ["firmwareVersion", "firmware", "softwareVersion", "version"]) {
            return text
        }
        if let info = mirrorAny(device, key: "firmwareInfo") {
            return String(describing: info)
        }
        // DeviceState sometimes carries version-ish fields after link-up.
        return "unknown (iOS Device API has no public firmware field; use Meta AI → Device → About)"
    }

    private static func mirrorBool(_ object: Any, key: String) -> Bool? {
        let mirror = Mirror(reflecting: object)
        for child in mirror.children where child.label == key {
            if let value = child.value as? Bool { return value }
        }
        return nil
    }

    private static func mirrorString(_ object: Any, keys: [String]) -> String? {
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            guard let label = child.label, keys.contains(label) else { continue }
            if let text = child.value as? String, !text.isEmpty { return text }
            let described = String(describing: child.value)
            if described != "nil", !described.isEmpty { return described }
        }
        return nil
    }

    private static func mirrorAny(_ object: Any, key: String) -> Any? {
        Mirror(reflecting: object).children.first { $0.label == key }?.value
    }
}
