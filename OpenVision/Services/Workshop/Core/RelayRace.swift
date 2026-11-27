// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// A relay race: "ask Indy to find three caterers, then have Driver book the cheapest."
//
// One sentence names a chain of assistants. Each is asked in turn and is given the answer
// of the one before, so the wearer delegates a whole piece of work without waiting to
// carry each answer to the next assistant by hand.

import Foundation

enum RelayRace {
    struct Step: Equatable, Sendable {
        var bot: String
        var task: String
    }

    struct Plan: Equatable, Sendable {
        var steps: [Step]

        /// "Indy, then Driver".
        var spokenRoute: String {
            steps.map(\.bot).joined(separator: ", then ")
        }
    }

    /// The most steps in one chain. Each step is a request, and a longer chain is slow
    /// enough that the wearer has stopped listening.
    static let stepLimit = 4
    /// The most of one assistant's answer handed to the next.
    static let carryLimit = 3_000

    private static let joins = [" and then ", " then ", " after that "]

    /// Reads a chain from a sentence. Returns nil unless at least two steps each name one
    /// of the wearer's assistants: anything less is an ordinary request.
    static func plan(_ utterance: String, bots: [String]) -> Plan? {
        // Commas go: the recognizer adds and drops them freely around "then".
        var text = utterance
            .replacingOccurrences(of: "’", with: "'")
            .map { ",;".contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let lower = text.lowercased()
        for lead in ["hey phoenix ", "ok phoenix ", "okay phoenix ", "phoenix ", "please "] where lower.hasPrefix(lead) {
            text = String(text.dropFirst(lead.count))
            break
        }

        var pieces = [text]
        for join in joins {
            pieces = pieces.flatMap { split($0, on: join) }
        }
        guard pieces.count >= 2 else { return nil }

        var steps: [Step] = []
        for piece in pieces {
            if let step = step(piece, bots: bots, first: steps.isEmpty) {
                steps.append(step)
            } else if let last = steps.indices.last {
                // "…find caterers, then pick the cheapest" is still the same assistant's work.
                steps[last].task += ", then " + piece.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
            } else {
                return nil
            }
        }
        guard (2...stepLimit).contains(steps.count) else { return nil }
        return Plan(steps: steps)
    }

    private static func split(_ text: String, on join: String) -> [String] {
        var pieces: [String] = []
        var rest = Substring(text)
        while let range = rest.range(of: join, options: .caseInsensitive) {
            pieces.append(String(rest[..<range.lowerBound]))
            rest = rest[range.upperBound...]
        }
        pieces.append(String(rest))
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// - Parameter first: False once an assistant has been named. After that the short
    ///   form "then Driver to price it" is enough.
    private static func step(_ piece: String, bots: [String], first: Bool) -> Step? {
        let trimmed = piece.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        let lower = trimmed.lowercased()
        for bot in bots.sorted(by: { $0.count > $1.count }) {
            let name = bot.lowercased()
            var leads = [
                "ask \(name) to ", "tell \(name) to ", "have \(name) ", "get \(name) to ", "let \(name) ",
                "\(name) should ", "\(name) can ", "pass it to \(name) to ", "give it to \(name) to ",
                "send it to \(name) to ", "hand it to \(name) to ", "ask \(name) ",
            ]
            if !first { leads.append("\(name) to ") }
            for lead in leads where lower.hasPrefix(lead) {
                let task = String(trimmed.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
                guard !task.isEmpty else { return nil }
                return Step(bot: bot, task: WorkshopText.sentence(task))
            }
        }
        return nil
    }

    /// What a step's assistant is sent.
    ///
    /// - Parameter earlier: The steps before this one, with the answers they gave.
    static func prompt(for step: Step, number: Int, of total: Int, earlier: [(step: Step, answer: String)]) -> String {
        guard let last = earlier.last else {
            return total > 1
                ? "\(step.task)\n\nThis is step 1 of \(total). Your answer will be handed to another assistant, so make it complete and short."
                : step.task
        }
        var answer = last.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if answer.count > carryLimit {
            answer = String(answer.prefix(carryLimit)) + "\n[The rest was cut off.]"
        }
        return """
        \(step.task)

        This is step \(number) of \(total) in a chain. \(last.step.bot) was asked: "\(last.step.task)" and answered:

        \(answer)
        """
    }

    /// What is said when a step does not answer, so the chain stops there.
    static func spokenStopped(at index: Int, plan: Plan) -> String {
        let step = plan.steps[index]
        let waiting = plan.steps[(index + 1)...].map(\.bot)
        if waiting.isEmpty {
            return "\(step.bot) did not answer."
        }
        return "\(step.bot) did not answer, so I stopped before \(WorkshopText.list(Array(waiting)))."
    }
}
