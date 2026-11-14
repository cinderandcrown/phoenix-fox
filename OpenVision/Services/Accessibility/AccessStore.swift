// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Where the accessibility suite keeps what it must remember: saved faces, routines,
// reminders, the activity trail, and saved transcripts.
//
// Every file is sealed with AES-GCM. The key lives in the Keychain, is never synced, and
// cannot be restored onto another device, so a backup of these files is unreadable
// anywhere but this phone.

import CryptoKit
import Foundation
import Security

enum AccessStore {
    static func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let key = key(),
              let sealed = try? Data(contentsOf: file(name)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let clear = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(type, from: clear)
    }

    /// - Returns: False when the value could not be written, so the caller can say so.
    @discardableResult
    static func save<Value: Encodable>(_ value: Value, to name: String) -> Bool {
        guard let key = key(),
              let clear = try? JSONEncoder().encode(value),
              let combined = try? AES.GCM.seal(clear, using: key).combined else { return false }
        do {
            // Readable after the first unlock, so a sound alert can still be handled while
            // the phone is locked in a pocket.
            try combined.write(to: file(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: file(name))
    }

    private static func file(_ name: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("Accessibility", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
        return folder.appendingPathComponent(name + ".sealed")
    }

    private static let lock = NSLock()
    private static let account = "phoenix.accessibility.key"

    /// The key, made on first use. Nil only when the Keychain refuses, in which case nothing
    /// is read or written: data is never stored unsealed as a fallback.
    private static func key() -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else { return nil }
        let fresh = SymmetricKey(size: .bits256)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: fresh.withUnsafeBytes { Data($0) },
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? fresh : nil
    }
}
