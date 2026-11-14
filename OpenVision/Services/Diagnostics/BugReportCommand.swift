// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Fixed phrases that open the beta feedback sheet. Matched on the phone so
// "report a bug" never reaches a bot by mistake.

import Foundation

enum BugReportCommand: Equatable, Sendable {
    case report(note: String)

    static func parse(_ utterance: String) -> BugReportCommand? {
        let loose = utterance
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !loose.isEmpty else { return nil }

        let triggers = [
            "report a bug",
            "file a bug",
            "send feedback",
            "send a bug report",
            "file a bug report",
            "report bug",
            "feedback report",
        ]
        guard let trigger = triggers.first(where: { loose.contains($0) }) else { return nil }

        var note = loose
        if let range = note.range(of: trigger) {
            note.removeSubrange(range)
        }
        // Drop a leading wake word if the recognizer left it on.
        for wake in ["jarvis,", "jarvis", "hey jarvis"] {
            if note.hasPrefix(wake) {
                note = String(note.dropFirst(wake.count))
            }
        }
        note = note
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.-")))
        return .report(note: note)
    }
}
