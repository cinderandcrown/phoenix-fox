// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// Recent redacted log lines for a feedback report. Cap keeps the payload small.
final class DiagnosticsRingBuffer: @unchecked Sendable {
    static let shared = DiagnosticsRingBuffer()

    struct Entry: Sendable, Equatable {
        var at: Date
        var category: String
        var level: String
        var message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let capacity: Int

    init(capacity: Int = 80) {
        self.capacity = max(capacity, 8)
    }

    func append(category: String, level: String, message: String) {
        let entry = Entry(
            at: Date(),
            category: String(category.prefix(64)),
            level: String(level.prefix(16)),
            message: String(LogRedactor.redact(message).prefix(500))
        )
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    func snapshot() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        let formatter = ISO8601DateFormatter()
        return entries.map { entry in
            [
                "at": formatter.string(from: entry.at),
                "category": entry.category,
                "level": entry.level,
                "message": entry.message,
            ]
        }
    }

    /// Test helper.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
