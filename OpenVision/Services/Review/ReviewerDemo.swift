// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// App Review path without glasses (Guideline 2.1). Pure logic for unit tests.
// Clock answers are always available (no cloud). Extra help lines only in demo mode.

import Foundation

enum ReviewerDemo {
    static let defaultsKey = "ov.reviewerDemoEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setEnabled(_ on: Bool, defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: defaultsKey)
    }

    static let banner = "App Review demo — phone mic and speaker, no glasses needed."

    /// Scripted replies. Time/date always; other lines only when `demoEnabled`.
    static func reply(
        to command: String,
        demoEnabled: Bool = isEnabled(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let words = command.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .joined(separator: " ")
            .replacingOccurrences(of: "’", with: "'")
        guard !words.isEmpty else { return nil }

        if words.contains("what time") || words == "time" || words.hasPrefix("what's the time")
            || words.hasPrefix("whats the time") || words.contains("what is the time") {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            formatter.calendar = calendar
            formatter.locale = .current
            return "It's \(formatter.string(from: now))."
        }

        if words.contains("what's the date") || words.contains("what is the date")
            || words.contains("what's today's date") || words.contains("what day is it") {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .none
            formatter.calendar = calendar
            formatter.locale = .current
            return formatter.string(from: now)
        }

        guard demoEnabled else { return nil }

        if words.contains("what can you do") || words == "help" || words.contains("what do you do") {
            return "I'm Jarvis in App Review demo. Ask what time it is, or open Settings for Privacy and Data, Voice, and Accessibility. Connect glasses later for the full hands-free path."
        }

        if words.contains("who are you") || words.contains("your name") {
            return "I'm Jarvis, the spoken voice of Phoenix Fox. This is the App Review demo on the phone."
        }

        if words.contains("privacy") {
            return "Open Settings, then Privacy and Data, for the privacy policy, cloud AI consent, and erase controls."
        }

        return nil
    }
}
