// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The council: one yes-or-no question put to every assistant at once.
//
// Four answers read out one after another are four opinions to hold in your head. The
// council asks each assistant for a one-word vote and one reason, counts the votes on the
// phone, and says the result with the disagreement first, because the one assistant who
// said no is usually what the wearer needs to hear.

import Foundation

enum Council {
    enum Choice: String, Equatable, Sendable {
        case yes, no, unsure
    }

    struct Ballot: Equatable, Sendable {
        var bot: String
        var choice: Choice
        var reason: String
    }

    /// What each assistant is sent.
    static func prompt(_ question: String, withPhoto: Bool) -> String {
        var lines = [
            "Council vote. Every assistant is being asked the same question and the votes will be counted.",
            "Question: \(question)",
        ]
        if withPhoto { lines.append("The photo shows what the wearer is looking at.") }
        lines.append("Reply with one word on the first line: YES, NO, or UNSURE. On the second line give your reason in one short sentence. Do not ask a question back.")
        return lines.joined(separator: "\n")
    }

    /// Reads one assistant's reply. A reply that does not start with a vote is counted as
    /// unsure, with the reply as its reason, so a long answer is heard and not thrown away.
    static func ballot(bot: String, reply: String) -> Ballot {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = WorkshopText.words(trimmed)
        let first = words.first ?? ""
        let choice: Choice
        var reasonWords = Array(trimmed.split(whereSeparator: \.isWhitespace).map(String.init).dropFirst())
        switch first {
        case "yes", "yeah", "yep": choice = .yes
        case "no", "nope": choice = .no
        case "unsure", "maybe", "uncertain", "unclear": choice = .unsure
        default:
            choice = .unsure
            reasonWords = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return Ballot(bot: bot, choice: choice, reason: reason(reasonWords.joined(separator: " ")))
    }

    /// The first sentence of the reason, without the marks a model puts around it.
    private static func reason(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t-–—:;,.*#"))
        for lead in ["Reason: ", "reason: ", "Because ", "because "] where cleaned.hasPrefix(lead) {
            cleaned = String(cleaned.dropFirst(lead.count))
        }
        if let end = cleaned.firstIndex(where: { ".!?\n".contains($0) }) {
            cleaned = String(cleaned[..<end])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        if cleaned.count > 220 { cleaned = String(cleaned.prefix(220)) + "…" }
        return cleaned
    }

    struct Verdict: Equatable, Sendable {
        var ballots: [Ballot]
        /// Assistants that were asked and did not answer.
        var silent: [String]

        func count(_ choice: Choice) -> Int { ballots.filter { $0.choice == choice }.count }

        /// The side with the most votes, or nil when yes and no are level or nobody took a side.
        var leading: Choice? {
            let yes = count(.yes), no = count(.no)
            if yes == no { return nil }
            return yes > no ? .yes : .no
        }

        /// One line for the day sheet: "3 yes, 1 no".
        var tally: String {
            var parts: [String] = []
            for choice in [Choice.yes, .no, .unsure] where count(choice) > 0 {
                parts.append("\(count(choice)) \(choice.rawValue)")
            }
            return parts.isEmpty ? "no answers" : parts.joined(separator: ", ")
        }
    }

    /// Counts the replies.
    ///
    /// - Parameters:
    ///   - replies: Each assistant's reply. An assistant that replied twice is counted once,
    ///     by its last reply.
    ///   - asked: The assistants that were asked, so the ones that stayed silent can be named.
    static func verdict(replies: [(bot: String, text: String)], asked: [String]) -> Verdict {
        var ballots: [Ballot] = []
        for reply in replies where !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let ballot = ballot(bot: reply.bot, reply: reply.text)
            if let index = ballots.firstIndex(where: { same($0.bot, reply.bot) }) {
                ballots[index] = ballot
            } else {
                ballots.append(ballot)
            }
        }
        let silent = asked.filter { name in !ballots.contains { same($0.bot, name) } }
        return Verdict(ballots: ballots, silent: silent)
    }

    private static func same(_ one: String, _ other: String) -> Bool {
        one.compare(other, options: .caseInsensitive) == .orderedSame
    }

    /// The verdict, said aloud: the count, then the dissent, then one reason from the majority.
    static func spoken(_ verdict: Verdict) -> String {
        guard !verdict.ballots.isEmpty else { return "Nobody on the council answered." }
        var parts: [String] = []
        let yes = verdict.ballots.filter { $0.choice == .yes }
        let no = verdict.ballots.filter { $0.choice == .no }
        let unsure = verdict.ballots.filter { $0.choice == .unsure }

        if verdict.ballots.count == 1 {
            let only = verdict.ballots[0]
            parts.append("Only \(only.bot) answered, and \(only.choice == .unsure ? "is unsure" : "says \(only.choice.rawValue)")\(said(only.reason))")
        } else if let side = verdict.leading {
            let winners = side == .yes ? yes : no
            let losers = side == .yes ? no : yes
            if losers.isEmpty, unsure.isEmpty {
                parts.append("\(everyone(winners.count)) say \(side.rawValue).")
            } else {
                parts.append("\(counted(winners.count, say: side.rawValue)), \(others(losers, unsure, opposite: side == .yes ? "no" : "yes")).")
            }
            for ballot in losers + unsure {
                parts.append("\(ballot.bot) \(ballot.choice == .unsure ? "is unsure" : "says \(ballot.choice.rawValue)")\(said(ballot.reason))")
            }
            if let first = winners.first {
                parts.append("For \(side.rawValue), \(first.bot)\(said(first.reason))")
            }
        } else if yes.isEmpty, no.isEmpty {
            parts.append("Nobody would say yes or no.")
            for ballot in unsure.prefix(2) {
                parts.append("\(ballot.bot)\(said(ballot.reason))")
            }
        } else {
            parts.append("The council is split, \(yes.count) to \(no.count).")
            if let first = yes.first { parts.append("For yes, \(first.bot)\(said(first.reason))") }
            if let first = no.first { parts.append("For no, \(first.bot)\(said(first.reason))") }
        }
        if !verdict.silent.isEmpty {
            parts.append("\(WorkshopText.list(verdict.silent)) did not answer.")
        }
        return parts.joined(separator: " ")
    }

    /// The end of a line about one assistant: ": its reason." or a full stop.
    private static func said(_ reason: String) -> String {
        reason.isEmpty ? "." : ": \(reason)."
    }

    private static func everyone(_ count: Int) -> String {
        count == 2 ? "Both" : "All \(count)"
    }

    private static func counted(_ count: Int, say word: String) -> String {
        "\(count) \(count == 1 ? "says" : "say") \(word)"
    }

    private static func others(_ losers: [Ballot], _ unsure: [Ballot], opposite: String) -> String {
        var parts: [String] = []
        if !losers.isEmpty { parts.append(counted(losers.count, say: opposite)) }
        if !unsure.isEmpty { parts.append("\(unsure.count) \(unsure.count == 1 ? "is" : "are") unsure") }
        return parts.joined(separator: ", ")
    }
}
