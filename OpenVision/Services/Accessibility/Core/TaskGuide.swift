// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Walks the wearer through a task one step at a time.
//
// Only one step is ever spoken, and nothing moves on until the wearer says so. The place
// in the task is saved, so after an interruption "what was I doing?" has an exact answer.

import Foundation

struct Routine: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var steps: [String]

    var id: String { name.lowercased() }

    /// Splits spoken or written instructions into steps.
    ///
    /// Handles a numbered list from a model ("1. Fill the kettle 2. Turn it on"), one step
    /// per line, and a spoken run joined with "then".
    static func steps(from text: String) -> [String] {
        // List markers become line breaks, so every kind of list is then one step per line.
        let marked = text
            .replacingOccurrences(of: #"(^|\s)\d{1,2}[.):]\s"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(
                of: #"(^|\s)step\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})[:,.]?\s+"#,
                with: "\n", options: [.regularExpression, .caseInsensitive]
            )
        var pieces = marked.split(whereSeparator: \.isNewline).map(String.init)
        if pieces.count <= 1 {
            pieces = text
                .replacingOccurrences(of: #"[,;.]?\s+(and then|then|after that|next,)\s+"#, with: "\n", options: [.regularExpression, .caseInsensitive])
                .split(whereSeparator: \.isNewline).map(String.init)
        }
        if pieces.count <= 1 {
            pieces = text.split(separator: ";").map(String.init)
        }
        return pieces.compactMap(clean)
    }

    /// Strips list markers and a leading "step two:" so only the instruction is left.
    private static func clean(_ piece: String) -> String? {
        var text = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in [#"^[-*•]\s*"#, #"^\d{1,2}[.):]\s*"#, #"^(first|second|third|finally|lastly),?\s+"#, #"^step\s+\w+[:,.]?\s+"#] {
            text = text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        guard text.count > 1 else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// A task in progress.
struct TaskRun: Codable, Equatable, Sendable {
    var routine: Routine
    var index = 0
    var startedAt: Date
    /// When a step was last spoken, for the gentle reminder after a long silence.
    var lastSpokenAt: Date
    var finished = false

    init(_ routine: Routine, at now: Date) {
        self.routine = routine
        startedAt = now
        lastSpokenAt = now
    }

    var position: String { "Step \(index + 1) of \(routine.steps.count)" }

    /// The first step, with how to move on. Said once, when the task starts.
    mutating func begin(at now: Date) -> String {
        lastSpokenAt = now
        guard !routine.steps.isEmpty else {
            finished = true
            return "\(routine.name) has no steps yet."
        }
        let count = routine.steps.count
        return "\(routine.name), \(count) step\(count == 1 ? "" : "s"). Say next when you finish each one. \(position). \(routine.steps[0])."
    }

    mutating func next(at now: Date) -> String {
        lastSpokenAt = now
        guard !finished else { return "\(routine.name) is already finished." }
        guard index + 1 < routine.steps.count else {
            finished = true
            return "That was the last step. \(routine.name) is done."
        }
        index += 1
        return current
    }

    mutating func back(at now: Date) -> String {
        lastSpokenAt = now
        guard index > 0 else { return "This is the first step. \(current)" }
        index -= 1
        finished = false
        return current
    }

    mutating func repeated(at now: Date) -> String {
        lastSpokenAt = now
        return current
    }

    /// Where the wearer is, said in full for "what was I doing?".
    var summary: String {
        finished
            ? "You finished \(routine.name)."
            : "You are doing \(routine.name). \(position): \(routine.steps[index]). Say next when it's done."
    }

    /// A reminder of the current step after a long quiet stretch, or nil if it is too soon.
    mutating func nudge(at now: Date, after quiet: TimeInterval = 240) -> String? {
        guard !finished, now.timeIntervalSince(lastSpokenAt) >= quiet else { return nil }
        lastSpokenAt = now
        return "Still on \(routine.name). \(current) Say next, repeat, or stop the task."
    }

    private var current: String { "\(position). \(routine.steps[index])." }
}

/// A reminder that waits for a person, not a time or a place.
struct PersonReminder: Codable, Equatable, Sendable {
    var person: String
    var note: String
    var createdAt: Date

    /// Removes and returns the notes waiting for this person.
    static func take(for person: String, from reminders: inout [PersonReminder]) -> [String] {
        let name = person.lowercased()
        let due = reminders.filter { $0.person.lowercased() == name }
        reminders.removeAll { $0.person.lowercased() == name }
        return due.map(\.note)
    }
}
