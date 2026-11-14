// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Answers "what was I doing?".
//
// The trail is a short list of things the wearer started through Phoenix Fox: a task, a
// walk, something read aloud, a reminder. It is not a recording. It holds no ambient
// speech and no photos, only one line per activity, and it is kept only when the wearer
// has turned recall on.

import Foundation

struct ActivityEntry: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case task, walk, read, reminder, asked, captions
    }

    var at: Date
    var kind: Kind
    /// Worded to follow "you": "started making tea", "asked me to read a label".
    var summary: String
}

enum ActivityTrail {
    /// Entries older than this are dropped when the trail is saved.
    static let keepFor: TimeInterval = 24 * 3600
    static let capacity = 60

    static func appending(_ entry: ActivityEntry, to entries: [ActivityEntry]) -> [ActivityEntry] {
        var kept = entries.filter { entry.at.timeIntervalSince($0.at) < keepFor }
        // Saying the same thing twice in a row is one activity.
        if let last = kept.last, last.kind == entry.kind, last.summary == entry.summary {
            kept.removeLast()
        }
        kept.append(entry)
        return Array(kept.suffix(capacity))
    }

    /// The answer, most useful part first: whatever is still in progress, then the last
    /// few things from the past couple of hours.
    ///
    /// - Parameters:
    ///   - inProgress: Sentences for things happening right now, such as a task's current step.
    ///   - enabled: Whether the wearer has turned recall on.
    static func recall(entries: [ActivityEntry], inProgress: [String], enabled: Bool, now: Date) -> String {
        var parts = inProgress
        let recent = entries
            .filter { now.timeIntervalSince($0.at) < 2 * 3600 && now.timeIntervalSince($0.at) >= 0 }
            .suffix(3)
            .reversed()
        for (offset, entry) in recent.enumerated() {
            let lead = offset == 0 && parts.isEmpty ? "" : "Before that, "
            let when = ago(now.timeIntervalSince(entry.at))
            let sentence = "\(when), you \(entry.summary)."
            parts.append(lead.isEmpty ? sentence.prefix(1).uppercased() + sentence.dropFirst() : lead + sentence)
        }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return enabled
            ? "Nothing in the last two hours. I only keep track of things you start with me."
            : "Activity recall is off, so I haven't kept track. Say turn on activity recall, and I'll remember the tasks, walks, and reading you start. It stays on this phone."
    }

    static func ago(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        switch minutes {
        case ..<1: return "just now"
        case 1: return "a minute ago"
        case ..<60: return "\(minutes) minutes ago"
        case ..<120: return "about an hour ago"
        default: return "about \(minutes / 60) hours ago"
        }
    }
}
