// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Reads a medicine label back in a fixed, useful order: what it is, how to take it,
// when it expires, and the warnings.
//
// Nothing is reworded or summarized. Every sentence spoken is text that was on the label,
// because a model that paraphrases a dose can change it. A strength or a direction the
// camera did not read clearly is not spoken at all.

import Foundation

enum LabelReader {
    struct Reading: Equatable, Sendable {
        /// The line that carries the strength, such as "Lisinopril 10 mg tablets".
        var product: String?
        var directions: [String]
        var expiry: String?
        var warnings: [String]
        /// Lines that fit none of the groups above, in reading order.
        var other: [String]
        /// True when a line with a number in it was read with low confidence.
        var doubtful: Bool

        static let advice = "That is only what I can read. Check with a pharmacist or someone you trust before you take any medicine."

        var spoken: String {
            var parts: [String] = []
            parts.append(product ?? "I can't read the name and strength clearly")
            if !directions.isEmpty { parts.append("Directions: " + directions.joined(separator: ". ")) }
            if let expiry { parts.append(expiry) }
            if !warnings.isEmpty { parts.append("Warnings: " + warnings.joined(separator: ". ")) }
            if doubtful { parts.append("Some of the label was hard to read, so part of this may be missing") }
            return parts.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.joined(separator: ". ") + ". " + Self.advice
        }
    }

    /// Reads the label as medicine. Returns nil when it does not look like medicine, so the
    /// caller reads it as plain text with no medical framing.
    ///
    /// - Parameters:
    ///   - lines: The label's lines in reading order, each with the recognizer's confidence.
    ///   - trust: A line holding a number is only spoken as fact at or above this confidence.
    static func medicine(_ lines: [TextFragment], trust: Double = 0.8) -> Reading? {
        var reading = Reading(product: nil, directions: [], expiry: nil, warnings: [], other: [], doubtful: false)
        var sawStrength = false
        var sawDirections = false
        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            guard text.count > 1 else { continue }
            let lower = text.lowercased()
            let unclear = text.contains(where: \.isNumber) && line.confidence < trust
            if unclear { reading.doubtful = true }

            if contains(lower, expiryWords) {
                if !unclear { reading.expiry = text }
            } else if contains(lower, warningWords) {
                reading.warnings.append(text)
            } else if contains(" " + lower + " ", directionWords) {
                sawDirections = true
                if !unclear { reading.directions.append(text) }
            } else if hasStrength(lower) {
                sawStrength = true
                // A guessed number is worse than none, so an unclear strength is dropped.
                if unclear { continue }
                if reading.product == nil { reading.product = text } else { reading.other.append(text) }
            } else {
                reading.other.append(text)
            }
        }
        let everything = lines.map(\.text).joined(separator: " ").lowercased()
        let named = contains(everything, medicineWords)
        guard (sawStrength && sawDirections) || (named && (sawStrength || sawDirections)) else { return nil }
        return reading
    }

    /// A number followed by a unit of dose: "10 mg", "0.5mL", "500 mcg", "1,000 IU", "2.5%".
    static func hasStrength(_ lower: String) -> Bool {
        lower.range(of: #"\d[\d,.]*\s?((mg|mcg|µg|g|ml|iu|units?|meq)\b|%)"#, options: .regularExpression) != nil
    }

    private static func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// Verbs and phrases that only appear in instructions, matched from the start of a word
    /// so "house" is not "use". Words for the form of the product, such as "tablets", are
    /// left out: they are on the name line too.
    private static let directionWords = [
        " take ", " apply ", " inhale ", " inject ", " swallow ", " chew ", " instill ", " place ",
        " use ", " give ", " by mouth", " daily", " every ", " times a day", " as needed", " with food",
        " at bedtime",
    ]
    private static let warningWords = [
        "warning", "caution", "do not", "keep out of reach", "may cause", "avoid", "overdose",
        "allerg", "consult", "stop use", "poison",
    ]
    private static let expiryWords = ["exp ", "exp.", "exp:", "expires", "expiry", "use by", "use before", "discard after", "best before"]
    private static let medicineWords = ["rx#", "rx:", "rx ", "pharmacy", "prescription", "refill", "drug facts", "active ingredient", "tablet", "capsule", "caplet"]
}
