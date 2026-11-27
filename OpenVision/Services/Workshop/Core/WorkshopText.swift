// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Numbers as they are said: "twelve", "a hundred and three", "two dozen", "40".
//
// The speech recognizer writes some numbers as digits and some as words, and which it
// picks changes from one sentence to the next. A count that is right only for digits
// would be wrong half the time, so both are read here, on the phone.

import Foundation

enum SpokenNumber {
    /// The largest number understood. Past this a count is more likely a mishearing.
    static let limit = 9_999

    /// A number at the start of `words`, and how many words it took up.
    ///
    /// - Parameter articles: Whether a bare "a" or "an" counts as one, as in "a box of lids".
    static func leading(_ words: [String], articles: Bool = false) -> (value: Int, used: Int)? {
        guard let first = words.first else { return nil }

        if let digits = Int(first), first.allSatisfy(\.isNumber) {
            return scaled(digits, used: 1, in: words)
        }
        if first == "a" || first == "an" {
            let next = words.count > 1 ? words[1] : ""
            if next == "couple" {
                return within(2, used: words.count > 2 && words[2] == "of" ? 3 : 2)
            }
            if next == "dozen" { return within(12, used: 2) }
            if next == "hundred" || next == "thousand" {
                return wordNumber(["one"] + words.dropFirst())
            }
            return articles ? (1, 1) : nil
        }
        if first == "zero" { return (0, 1) }
        return wordNumber(words)
    }

    /// The number a whole phrase says, or nil when any word is not part of a number.
    static func value(_ text: String) -> Int? {
        let words = WorkshopText.words(text)
        guard let found = leading(words), found.used == words.count else { return nil }
        return found.value
    }

    private static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    private static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static func isNumberWord(_ word: String) -> Bool {
        units[word] != nil || teens[word] != nil || tens[word] != nil
    }

    private static func wordNumber(_ words: [String]) -> (value: Int, used: Int)? {
        var thousands = 0
        var current = 0
        var used = 0
        var afterScale = false

        loop: for (index, word) in words.enumerated() {
            if let unit = units[word] {
                // "twenty three" and "three", but not "three four" or "thirteen four".
                guard current % 10 == 0, current % 100 == 0 || current % 100 >= 20 else { break loop }
                current += unit
            } else if let teen = teens[word] {
                guard current % 100 == 0 else { break loop }
                current += teen
            } else if let ten = tens[word] {
                guard current % 100 == 0 else { break loop }
                current += ten
            } else if word == "hundred" {
                // "three hundred" and "twelve hundred".
                guard (1...99).contains(current) else { break loop }
                current *= 100
            } else if word == "thousand" {
                guard thousands == 0, (1...9).contains(current) else { break loop }
                thousands = current * 1_000
                current = 0
            } else if word == "and" {
                // Only as in "a hundred and three".
                let next = index + 1 < words.count ? words[index + 1] : ""
                guard afterScale, isNumberWord(next) else { break loop }
                continue
            } else {
                break loop
            }
            afterScale = word == "hundred" || word == "thousand"
            used = index + 1
        }
        guard used > 0 else { return nil }
        return scaled(thousands + current, used: used, in: words)
    }

    /// Applies a following "dozen", and refuses anything past the limit.
    private static func scaled(_ value: Int, used: Int, in words: [String]) -> (value: Int, used: Int)? {
        if used < words.count, words[used] == "dozen" {
            return within(value * 12, used: used + 1)
        }
        return within(value, used: used)
    }

    private static func within(_ value: Int, used: Int) -> (value: Int, used: Int)? {
        (0...limit).contains(value) ? (value, used) : nil
    }
}

/// How the workshop reads a sentence: lowercase words, no punctuation.
enum WorkshopText {
    /// The words of a sentence. "1,200" stays one number, and an apostrophe stays in its word.
    static func words(_ text: String, keepCase: Bool = false) -> [String] {
        let source = Array((keepCase ? text : text.lowercased()).replacingOccurrences(of: "’", with: "'"))
        var cleaned = ""
        cleaned.reserveCapacity(source.count)
        for (index, character) in source.enumerated() {
            if character.isLetter || character.isNumber || character == "'" {
                cleaned.append(character)
            } else if character == ",", index > 0, index + 1 < source.count,
                      source[index - 1].isNumber, source[index + 1].isNumber {
                continue
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// The sentence as the parsers match it, with the wake word and politeness removed.
    static func command(_ text: String) -> String {
        Said(text).text
    }

    /// The rest of `text` after the first of `leads` it starts with.
    static func after(_ text: String, _ leads: [String]) -> String? {
        for lead in leads {
            if text == lead { return "" }
            if text.hasPrefix(lead + " ") { return String(text.dropFirst(lead.count + 1)) }
        }
        return nil
    }

    /// A stored sentence: first letter capitalized, the rest as said.
    static func sentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }

    /// "1 item", "3 items".
    static func count(_ number: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(number) \(number == 1 ? singular : plural ?? singular + "s")"
    }

    /// "a", "a and b", "a, b, and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
        }
    }

    /// A date or a time as it is said and written here: "12:00 PM", "Nov 14, 2026 at 9:41 AM".
    ///
    /// The system puts narrow no-break spaces in these. They are swapped for plain ones, so
    /// the text is the same on every system version and safe in a report.
    static func stamp(_ date: Date, date dateStyle: DateFormatter.Style, time timeStyle: DateFormatter.Style,
                      calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func clock(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        stamp(date, date: .none, time: .short, calendar: calendar, locale: locale)
    }

    /// "40 minutes", "2 hours", "1 hour 20 minutes", "3 days".
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 1 { return "less than a minute" }
        if minutes < 60 { return count(minutes, "minute") }
        let hours = minutes / 60
        if hours >= 48 { return count(hours / 24, "day") }
        let rest = minutes % 60
        // Past a few hours the minutes are noise.
        if rest == 0 || hours >= 6 { return count(hours, "hour") }
        return "\(count(hours, "hour")) \(count(rest, "minute"))"
    }
}

/// One sentence, as it is matched and as it was said.
///
/// Commands are matched on lowercase words. What follows a command (a note, a question, a
/// name) is kept in the wearer's own capitals, so a report says "Dana" and not "dana".
struct Said: Equatable, Sendable {
    let lower: [String]
    let cased: [String]

    init(_ utterance: String) {
        var cased = WorkshopText.words(utterance, keepCase: true)
        var lower = cased.map { $0.lowercased() }
        let leads = [["hey", "phoenix"], ["ok", "phoenix"], ["okay", "phoenix"], ["phoenix"], ["please"], ["can", "you"], ["could", "you"], ["would", "you"],
                     ["i", "want", "you", "to"], ["i", "need", "you", "to"]]
        for lead in leads where lower.count > lead.count && Array(lower.prefix(lead.count)) == lead {
            lower.removeFirst(lead.count)
            cased.removeFirst(lead.count)
        }
        if lower.count > 1, lower.last == "please" {
            lower.removeLast()
            cased.removeLast()
        }
        self.lower = lower
        self.cased = cased
    }

    var text: String { lower.joined(separator: " ") }
    var isEmpty: Bool { lower.isEmpty }

    func `is`(_ phrases: [String]) -> Bool {
        phrases.contains(text)
    }

    /// What was said after the first of `leads` this starts with, in the wearer's capitals.
    /// An empty string when the lead was the whole sentence.
    func after(_ leads: [String]) -> String? {
        let text = self.text
        for lead in leads {
            if text == lead { return "" }
            if text.hasPrefix(lead + " ") {
                return cased.dropFirst(lead.split(separator: " ").count).joined(separator: " ")
            }
        }
        return nil
    }
}
