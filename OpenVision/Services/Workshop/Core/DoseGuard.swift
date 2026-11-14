// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// A log of medicine taken, and a warning when the same one is logged again too soon.
//
// This answers "did I take it?". It is not a schedule and gives no medical advice: it
// knows only what the wearer logged and, when the label said "every N hours", that
// number. The log is sealed on the phone and is never sent to an assistant.

import Foundation

struct Dose: Codable, Equatable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case label, spoken }

    var id: UUID
    /// The name as read from the label or as said.
    var name: String
    var at: Date
    /// The shortest time between doses the label gave, in hours.
    var gapHours: Double?
    var source: Source
}

struct DoseLog: Codable, Equatable, Sendable {
    private(set) var doses: [Dose] = []

    /// How long the log goes back.
    static let keepDays = 90

    enum Check: Equatable, Sendable {
        case clear
        /// The same medicine was logged `ago` seconds ago, inside the gap.
        case tooSoon(last: Dose, ago: TimeInterval, gapHours: Double, fromLabel: Bool)
    }

    /// Whether logging `name` now would be a second dose inside the gap.
    ///
    /// - Parameters:
    ///   - gapHours: The gap this label gave, if it gave one.
    ///   - fallbackHours: The gap to use when no label has given one for this medicine.
    func check(_ name: String, gapHours: Double?, fallbackHours: Double, now: Date) -> Check {
        guard let last = last(of: name) else { return .clear }
        let known = gapHours ?? last.gapHours
        let gap = known ?? fallbackHours
        let ago = now.timeIntervalSince(last.at)
        guard ago >= 0, ago < gap * 3_600 else { return .clear }
        return .tooSoon(last: last, ago: ago, gapHours: gap, fromLabel: known != nil)
    }

    @discardableResult
    mutating func log(_ name: String, gapHours: Double?, source: Dose.Source, id: UUID = UUID(), now: Date) -> Dose {
        let dose = Dose(
            id: id,
            name: Self.display(name),
            at: now,
            // A medicine named by voice keeps the gap its label gave the last time.
            gapHours: gapHours ?? last(of: name)?.gapHours,
            source: source
        )
        doses.append(dose)
        let cutoff = now.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        doses.removeAll { $0.at < cutoff }
        return dose
    }

    mutating func removeLast() -> Dose? {
        doses.popLast()
    }

    mutating func removeAll() {
        doses.removeAll()
    }

    /// The most recent dose whose name matches.
    func last(of name: String) -> Dose? {
        doses.last { Self.matches($0.name, name) }
    }

    func taken(on day: Date, calendar: Calendar) -> [Dose] {
        doses.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }

    /// The names in the log, most recent first, each medicine once.
    var names: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for dose in doses.reversed() where seen.insert(Self.nameWords(dose.name).joined(separator: " ")).inserted {
            result.append(dose.name)
        }
        return result
    }

    // MARK: - Names

    /// Whether a logged name is the medicine a shorter spoken name means: "Ibuprofen
    /// Tablets 200 mg" is "ibuprofen".
    static func matches(_ logged: String, _ asked: String) -> Bool {
        let have = Set(nameWords(logged))
        let want = nameWords(asked)
        guard !want.isEmpty, !have.isEmpty else { return false }
        return want.allSatisfy(have.contains) || Set(want).isSuperset(of: have)
    }

    /// The words of a name that identify it. Strengths and forms are left out, so a
    /// 200 mg and a 400 mg tablet of the same drug count as the same medicine.
    private static func nameWords(_ name: String) -> [String] {
        let form: Set<String> = [
            "my", "the", "a", "an", "of", "mg", "mcg", "ml", "g", "iu", "tablet", "tablets", "capsule", "capsules",
            "caplet", "caplets", "pill", "pills", "dose", "strength", "extra", "regular", "usp", "oral",
        ]
        return WorkshopText.words(name).filter { word in
            !form.contains(word) && !word.contains(where: \.isNumber)
        }
    }

    private static func display(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(80))
    }
}

enum DoseGuard {
    /// The shortest gap between doses that a label's directions give, in hours.
    ///
    /// Only plain statements are read: "every 4 to 6 hours", "every 8 hours", "once
    /// daily", "twice a day". Anything else returns nil and the wearer's own setting is used.
    static func gapHours(inDirections directions: [String]) -> Double? {
        let words = WorkshopText.words(directions.joined(separator: " "))
        for (index, word) in words.enumerated() where word == "every" {
            let rest = Array(words[(index + 1)...])
            guard let first = SpokenNumber.leading(rest) else { continue }
            var after = first.used
            // "4 to 6 hours" and "4 6 hours", which is what "4-6 hours" becomes.
            if after < rest.count, ["to", "or"].contains(rest[after]) { after += 1 }
            if let second = SpokenNumber.leading(Array(rest[after...])), after + second.used < rest.count,
               ["hours", "hour", "hrs", "hr"].contains(rest[after + second.used]) {
                return plausible(Double(min(first.value, second.value)))
            }
            if first.used < rest.count, ["hours", "hour", "hrs", "hr"].contains(rest[first.used]) {
                return plausible(Double(first.value))
            }
        }
        let text = " " + words.joined(separator: " ") + " "
        // A daily medicine taken a little early the next morning is not a double dose.
        if [" once daily ", " once a day ", " once per day ", " one time a day ", " once every day "].contains(where: text.contains) {
            return 20
        }
        if [" twice daily ", " twice a day ", " twice per day ", " two times a day ", " 2 times a day "].contains(where: text.contains) {
            return 8
        }
        return nil
    }

    private static func plausible(_ hours: Double) -> Double? {
        (1...72).contains(hours) ? hours : nil
    }

    // MARK: - Saying

    static func spokenLogged(_ dose: Dose, calendar: Calendar, locale: Locale = .current) -> String {
        var line = "Logged \(dose.name) at \(clock(dose.at, calendar: calendar, locale: locale))."
        if let gap = dose.gapHours {
            line += " The label says every \(hours(gap))."
        }
        return line + " Say \"undo that dose\" if this is wrong."
    }

    static func spokenTooSoon(last: Dose, ago: TimeInterval, gapHours: Double, fromLabel: Bool, calendar: Calendar, locale: Locale = .current) -> String {
        let reason = fromLabel
            ? "The label says every \(hours(gapHours))."
            : "That is inside the \(hours(gapHours)) you asked me to watch for."
        return "Wait. You logged \(last.name) \(WorkshopText.span(ago)) ago, at \(clock(last.at, calendar: calendar, locale: locale)). "
            + reason + " I have not logged another. If you did take it, say \"log it anyway\"."
    }

    /// The answer to "did I take my …?".
    static func spokenLast(of name: String, in log: DoseLog, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        guard let last = log.last(of: name) else {
            return "I have no \(name) in the log."
        }
        let ago = WorkshopText.span(now.timeIntervalSince(last.at))
        let time = clock(last.at, calendar: calendar, locale: locale)
        if calendar.isDate(last.at, inSameDayAs: now) {
            return "Yes. \(last.name) at \(time), \(ago) ago."
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(last.at, inSameDayAs: yesterday) {
            return "Not today. The last \(last.name) I have is yesterday at \(time), \(ago) ago."
        }
        return "Not today. The last \(last.name) I have is \(ago) ago."
    }

    static func spokenToday(_ log: DoseLog, now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        let today = log.taken(on: now, calendar: calendar)
        guard !today.isEmpty else { return "Nothing is logged today." }
        let lines = today.map { "\($0.name) at \(clock($0.at, calendar: calendar, locale: locale))" }
        return "Today: \(WorkshopText.list(lines))."
    }

    private static func hours(_ value: Double) -> String {
        WorkshopText.count(Int(value.rounded()), "hour")
    }

    private static func clock(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        WorkshopText.clock(date, calendar: calendar, locale: locale)
    }
}

/// Two readings of the same thing, compared.
///
/// Text recognition can turn one drug name into another that looks like it. Reading twice
/// and speaking only what both readings agree on costs a second look and catches that.
enum TwoLooks {
    enum Outcome: Equatable, Sendable {
        case agreed(String)
        case disagreed(String, String)
        /// Neither look read anything.
        case unread
    }

    static func settle(_ first: String?, _ second: String?) -> Outcome {
        let one = first.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let two = second.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        switch (one, two) {
        case (nil, nil): return .unread
        case (let only?, nil), (nil, let only?): return .disagreed(only, "")
        case (let one?, let two?):
            // Spacing is not a difference: "200 mg" and "200mg" are the same reading.
            return WorkshopText.words(one).joined() == WorkshopText.words(two).joined() ? .agreed(one) : .disagreed(one, two)
        }
    }
}
