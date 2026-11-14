// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Tells banknotes apart from the words and numbers printed on them.
//
// A note repeats its value many times: numerals in the corners and the amount spelled out.
// The reader counts that evidence and answers only when one value clearly wins. A wrong
// answer here costs the wearer money, so "I can't tell" is a correct result.

import Foundation

enum CurrencyReader {
    enum Reading: Equatable, Sendable {
        case note(value: Int, currency: String)
        /// It is a banknote, but the value could not be read with confidence.
        case unsure(currency: String)
        case notMoney

        var spoken: String {
            switch self {
            case .note(let value, let currency):
                return "\(value) \(value == 1 ? currency : Self.plural(currency))."
            case .unsure(let currency):
                return "This looks like a \(currency) note, but I can't read its value. Hold it flat, a little closer, and ask again."
            case .notMoney:
                return "I don't see a banknote I know. I can read US dollars, euros, British pounds, and Canadian dollars, but not coins. Hold the note flat and ask again."
            }
        }

        private static func plural(_ currency: String) -> String {
            currency == "euro" ? "euros" : currency + "s"
        }
    }

    /// - Parameter texts: Every piece of text recognized in the photo, in any order.
    static func read(_ texts: [String]) -> Reading {
        let upper = texts.map { $0.uppercased() }
        let joined = " " + upper.joined(separator: " ").replacingOccurrences(of: "\n", with: " ") + " "
        guard let currency = currencies.first(where: { currency in
            currency.marks.contains { joined.contains($0) }
        }) else { return .notMoney }

        var scores: [Int: Int] = [:]
        // The amount in words is the strongest sign. Longer phrases are matched first and
        // removed, so "ONE HUNDRED DOLLARS" is never also counted as "ONE".
        var remaining = joined
        for (phrase, value) in currency.words.sorted(by: { $0.key.count > $1.key.count }) {
            let pieces = remaining.components(separatedBy: phrase)
            if pieces.count > 1 {
                scores[value, default: 0] += 3 * (pieces.count - 1)
                remaining = pieces.joined(separator: " ")
            }
        }
        // Corner numerals: only a fragment that is the number by itself counts. Serial
        // numbers and years are longer runs of digits and are ignored.
        for text in upper {
            for token in text.split(whereSeparator: { !$0.isNumber && !$0.isLetter }) {
                if let value = Int(token), currency.values.contains(value) {
                    scores[value, default: 0] += 1
                }
            }
        }
        let ranked = scores.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        guard let top = ranked.first, top.value >= 2 else { return .unsure(currency: currency.name) }
        if ranked.count > 1, ranked[1].value * 2 > top.value { return .unsure(currency: currency.name) }
        return .note(value: top.key, currency: currency.name)
    }

    private struct Currency {
        var name: String
        /// Text that appears on every note of this currency and marks it as money.
        var marks: [String]
        var values: Set<Int>
        var words: [String: Int]
    }

    private static let currencies: [Currency] = [
        Currency(
            name: "dollar",
            marks: ["FEDERAL RESERVE NOTE", "UNITED STATES OF AMERICA", "THIS NOTE IS LEGAL TENDER"],
            values: [1, 2, 5, 10, 20, 50, 100],
            words: [
                "ONE DOLLAR": 1, "TWO DOLLARS": 2, "FIVE DOLLARS": 5, "TEN DOLLARS": 10,
                "TWENTY DOLLARS": 20, "FIFTY DOLLARS": 50, "ONE HUNDRED DOLLARS": 100,
            ]
        ),
        Currency(
            name: "Canadian dollar",
            marks: ["BANK OF CANADA", "BANQUE DU CANADA"],
            values: [5, 10, 20, 50, 100],
            words: [
                "FIVE DOLLARS": 5, "TEN DOLLARS": 10, "TWENTY DOLLARS": 20,
                "FIFTY DOLLARS": 50, "ONE HUNDRED DOLLARS": 100,
                "CINQ DOLLARS": 5, "DIX DOLLARS": 10, "VINGT DOLLARS": 20,
                "CINQUANTE DOLLARS": 50, "CENT DOLLARS": 100,
            ]
        ),
        Currency(
            name: "pound",
            marks: ["BANK OF ENGLAND"],
            values: [5, 10, 20, 50],
            words: ["FIVE POUNDS": 5, "TEN POUNDS": 10, "TWENTY POUNDS": 20, "FIFTY POUNDS": 50]
        ),
        Currency(
            name: "euro",
            marks: [" EURO ", " EYPΩ ", " ЕВРО "],
            values: [5, 10, 20, 50, 100, 200, 500],
            words: [:]
        ),
    ]
}
