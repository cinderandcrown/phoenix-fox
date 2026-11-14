// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// How Jarvis talks: plain words, a short first part, and a quick word that it heard you.
//
// A model writes for a screen. Asterisks, headings, bullets, and web addresses are noise in
// an ear. `SpokenReply.plain` turns written text into something a voice can say, and
// `SpokenReply.parts` keeps a long answer from running on: the first part is spoken and the
// rest waits for "go on". The full text always stays in History on the phone.

import Foundation

enum SpokenReply {
    /// About half a minute of speech. A longer answer pauses here.
    static let wordLimit = 70
    /// An answer this much over the limit is spoken whole: stopping for a few words is worse.
    static let slack = 15

    /// Said after the first part of a long answer.
    static let moreCue = "There's more. Say go on."

    // MARK: - Plain words

    /// `text` as a voice should say it: no markup, no web addresses, no emoji.
    static func plain(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")

        // Code is for reading. It stays on the phone.
        s = replace(s, "```[\\s\\S]*?```", " ")
        // Images and links keep their words and lose their addresses.
        s = replace(s, "!\\[([^\\]]*)\\]\\([^)]*\\)", "$1")
        s = replace(s, "\\[([^\\]]+)\\]\\([^)]*\\)", "$1")
        // A bare address is said as the site's name.
        s = replace(s, "https?://(?:www\\.)?([A-Za-z0-9.-]+)[^\\s]*?(?=[.,;:!?)\\]]*(?:\\s|$))", "$1")

        var lines: [String] = []
        for raw in s.components(separatedBy: "\n") {
            var line = raw
            // Rules and the dividers of a table are only drawing.
            if matches(line, "^\\s*([-*_=]\\s*){3,}$") || matches(line, "^\\s*\\|?[\\s:|-]*-[\\s:|-]*\\|?\\s*$") { continue }
            line = replace(line, "^\\s{0,3}#{1,6}\\s+", "")
            line = replace(line, "^\\s*>+\\s?", "")
            line = replace(line, "^\\s*[-*+•]\\s+", "")
            // The cells of a table row are read as a list.
            if line.contains("|") {
                line = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A line that ends without a stop gets one, so the voice pauses where the eye would.
            // Closing marks are looked through: "**Done.**" already has its stop.
            let words = line.trimmingCharacters(in: CharacterSet(charactersIn: "*_`~ "))
            if let last = words.last, !".!?:;,".contains(last) { line += "." }
            lines.append(line)
        }
        s = lines.joined(separator: " ")

        s = replace(s, "\\*\\*(.+?)\\*\\*", "$1")
        s = replace(s, "__(.+?)__", "$1")
        s = replace(s, "~~(.+?)~~", "$1")
        s = replace(s, "(?<![A-Za-z0-9*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![A-Za-z0-9*])", "$1")
        s = replace(s, "(?<![A-Za-z0-9_])_(?!\\s)(.+?)(?<!\\s)_(?![A-Za-z0-9_])", "$1")
        s = replace(s, "`([^`]*)`", "$1")
        // A mark whose partner is in another piece of a streamed answer is still only a mark.
        s = replace(s, "\\*{2,}|_{2,}|`+", "")

        s = String(String.UnicodeScalarView(s.unicodeScalars.filter { !isPicture($0) }))
        // Strip thousands separators so "1,200" is spoken as a number, not chopped at the comma.
        // Clock times (3:15, 15:30) are left for the voice engine — Premium/Enhanced AVSpeech
        // and Kokoro already read them naturally; rewriting them often sounds worse.
        s = replace(s, "\\b(\\d{1,3}(?:,\\d{3})+)\\b") { match in
            // match[0] is the full match; digits with commas live in group 1 when using replace(_:template).
            match.replacingOccurrences(of: ",", with: "")
        }
        s = replace(s, "\\s+", " ")
        s = replace(s, "\\s+([.,;:!?])", "$1")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Regex replace with a closure over the full match string.
    private static func replace(_ text: String, _ pattern: String, _ each: (String) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let full = ns.substring(with: match.range)
            if let swiftRange = Range(match.range, in: result) {
                result.replaceSubrange(swiftRange, with: each(full))
            }
        }
        return result
    }

    /// Emoji and the invisible characters that join them. A voice either skips them or
    /// reads out their names.
    private static func isPicture(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200D || scalar.value == 0xFE0F || scalar.value == 0x20E3 { return true }
        if (0x1F3FB...0x1F3FF).contains(scalar.value) { return true }
        return scalar.properties.isEmojiPresentation
    }

    // MARK: - A short first part

    struct Parts: Equatable, Sendable {
        /// What to say now.
        let now: String
        /// What waits for "go on", if the answer was long.
        let later: String?
    }

    /// Splits a long answer at the end of a sentence near `wordLimit`.
    ///
    /// A sentence is never cut. The first sentence is always spoken, however long.
    static func parts(_ text: String, wordLimit: Int = wordLimit, slack: Int = slack) -> Parts {
        let whole = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words(in: whole) > wordLimit + slack else { return Parts(now: whole, later: nil) }
        let all = sentences(whole)
        guard all.count > 1 else { return Parts(now: whole, later: nil) }

        var now: [String] = []
        var count = 0
        for sentence in all {
            let size = words(in: sentence)
            if !now.isEmpty && count + size > wordLimit { break }
            now.append(sentence)
            count += size
        }
        guard now.count < all.count else { return Parts(now: whole, later: nil) }
        return Parts(now: now.joined(separator: " "), later: all[now.count...].joined(separator: " "))
    }

    // MARK: - A whole turn

    struct Turn: Equatable, Sendable {
        /// What to say now, one line for each reply that had something to say. `index` is
        /// the reply's place in the list that was given.
        let lines: [Line]
        /// What waits for "go on".
        let later: String?

        struct Line: Equatable, Sendable {
            let index: Int
            let text: String
        }
    }

    /// Shapes the replies to one request for the ear.
    ///
    /// Each reply is put in plain words. With `short` on, long replies pause, the held
    /// parts are kept together for "go on", and the cue is said once, after the last line.
    /// When several assistants answered they share the time, so one cannot crowd out the rest.
    static func turn(_ replies: [(text: String, from: String)], short: Bool) -> Turn {
        let spoken = replies.enumerated()
            .map { (index: $0.offset, text: plain($0.element.text), from: $0.element.from) }
            .filter { !$0.text.isEmpty }
        guard short, !spoken.isEmpty else {
            return Turn(lines: spoken.map { Turn.Line(index: $0.index, text: $0.text) }, later: nil)
        }
        let several = spoken.count > 1
        let limit = max(25, wordLimit / spoken.count)
        var lines: [Turn.Line] = []
        var held: [String] = []
        for reply in spoken {
            let parts = parts(reply.text, wordLimit: limit, slack: several ? slack / 2 : slack)
            lines.append(Turn.Line(index: reply.index, text: parts.now))
            if let later = parts.later {
                let name = reply.from.trimmingCharacters(in: .whitespaces)
                held.append(several && !name.isEmpty ? "\(name) went on: \(later)" : later)
            }
        }
        guard !held.isEmpty, let last = lines.popLast() else { return Turn(lines: lines, later: nil) }
        lines.append(Turn.Line(index: last.index, text: last.text + " " + moreCue))
        return Turn(lines: lines, later: held.joined(separator: " "))
    }

    /// The next part of a held answer, with the cue again if there is still more.
    static func next(of held: String) -> Parts {
        let parts = parts(held)
        guard let later = parts.later else { return parts }
        return Parts(now: parts.now + " " + moreCue, later: later)
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// `text` as sentences. A stop counts when a space and a capital, digit, or quote follow.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            current.append(character)
            if ".!?".contains(character) {
                var next = index + 1
                // Closing quotes and brackets belong to the sentence they close.
                while next < characters.count, "\"”’')]".contains(characters[next]) {
                    current.append(characters[next])
                    next += 1
                }
                var afterSpace = next
                while afterSpace < characters.count, characters[afterSpace].isWhitespace { afterSpace += 1 }
                let startsSentence = afterSpace < characters.count
                    && (characters[afterSpace].isUppercase || characters[afterSpace].isNumber || "\"“‘'".contains(characters[afterSpace]))
                if afterSpace > next && startsSentence {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    index = afterSpace
                    continue
                }
                index = next
                continue
            }
            index += 1
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    /// True when the wearer asked for the rest of a long answer.
    static func asksForMore(_ command: String) -> Bool {
        let said = command.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .joined(separator: " ")
            .replacingOccurrences(of: "’", with: "'")
        return ["go on", "keep going", "continue", "carry on", "read the rest", "tell me the rest", "what's the rest", "and the rest"].contains(said)
    }

    // MARK: - Regular expressions

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return text }
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// How Jarvis acknowledges a request before the answer exists.
///
/// Named routes ("Asking Indy.") are spoken — the wearer can't see where it went.
/// Generic boilerplate ("On it.") is a short earcon instead, so the voice stays calm
/// and human when the real answer arrives.
enum Acknowledgement {
    /// Legacy spoken fillers kept for tests of the naming rules. Production uses `cue`.
    static let plain = ["On it.", "One moment.", "Right away."]

    enum Cue: Equatable, Sendable {
        /// Short chime — request accepted, no spoken boilerplate.
        case earcon
        /// Spoken acknowledgment with useful information (who was asked, looking).
        case speak(String)
    }

    /// Prefer this over `line` for the live path.
    static func cue(targetBot: String?, bots: [AssistantBot], photo: Bool, turn: Int) -> Cue {
        let spoken = line(targetBot: targetBot, bots: bots, photo: photo, turn: turn)
        if plain.contains(spoken) { return .earcon }
        return .speak(spoken)
    }

    /// - Parameters:
    ///   - targetBot: the assistant the wearer named, `AssistantBot.allBots`, or nil.
    ///   - photo: a photo is going with the request.
    ///   - turn: how many requests have been acknowledged, so the wording varies.
    static func line(targetBot: String?, bots: [AssistantBot], photo: Bool, turn: Int) -> String {
        let roster = AssistantRoster.normalized(bots)
        if let target = targetBot?.trimmingCharacters(in: .whitespaces), !target.isEmpty {
            if target.compare(AssistantBot.allBots, options: .caseInsensitive) == .orderedSame {
                return "Asking everyone."
            }
            let match = roster.first { $0.name.compare(target, options: .caseInsensitive) == .orderedSame }
            if let match, !match.isDefault {
                return "Asking \(match.name)."
            }
            if match == nil {
                return "Asking \(target)."
            }
        }
        if photo { return "Taking a look." }
        return plain[((turn % plain.count) + plain.count) % plain.count]
    }
}
