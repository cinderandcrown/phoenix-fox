// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Decides which assistant's window is in view, from the text and codes the phone read.
//
// Three things can say so, strongest first:
//
// 1. A marker: a QR code whose text is `PFX:BOT:` and the name.
// 2. A badge: a line that reads "TALK TO" and the name, and nothing else.
// 3. The name itself, where a window would show it: alone on a line, or in a short one.
//
// A name inside a sentence counts for little. "I'll pass this to Indy", read in Driver's
// window, must not move the target to Indy.
//
// The glasses camera points where the head points, so what is near the middle of the
// frame, left to right, is what the wearer is facing. Height matters much less: a
// window's title is at its top, above where anyone looks.

import Foundation

enum WindowReader {
    /// What a badge says before the name.
    static let badgeLeads: [[String]] = [["talk", "to"], ["look", "to", "talk"]]

    /// The recognizer's own confidence below which a fragment is not read at all.
    static let leastConfidence = 0.3

    static func read(_ view: ScreenView, roster: [LookName]) -> LookReading {
        var found: [LookCandidate] = []
        let typical = median(view.text.map(\.box.height))
        let folded = badgeLeads.map { $0.flatMap(words) }
        let leads = view.text.filter { folded.contains(words($0.text)) }.map(\.box)

        for entry in roster {
            let target = LookTarget.assistant(entry.bot)
            var scores: [LookCandidate] = []

            for code in view.codes where LookMarker.names(code.payload, entry) {
                scores.append(LookCandidate(target: target, score: facing(code.box), evidence: .marker, box: code.box))
            }
            let names = entry.all.map(words).filter { !$0.isEmpty }
            for fragment in view.text where fragment.confidence >= leastConfidence {
                let line = words(fragment.text)
                guard var (shape, evidence) = names.compactMap({ match($0, in: line) }).max(by: { $0.0 < $1.0 }) else { continue }
                // A badge on a narrow note wraps: "TALK TO" on one line and the name under it.
                if names.contains(line), leads.contains(where: { isAbove($0, fragment.box) }) {
                    (shape, evidence) = (1, .badge)
                }
                var score = shape * facing(fragment.box)
                if evidence != .badge {
                    score *= 0.7 + 0.3 * min(1, fragment.confidence)
                    // A title is set larger than what is under it. Small print is not a title.
                    if typical > 0 {
                        let size = fragment.box.height / typical
                        if size >= 1.25 { score *= 1.1 } else if size < 0.6 { score *= 0.8 }
                    }
                }
                scores.append(LookCandidate(target: target, score: min(1, score), evidence: evidence, box: fragment.box))
            }

            guard var best = scores.max(by: { $0.score < $1.score }) else { continue }
            // A chat window shows its assistant's name more than once: the title, and
            // beside each thing it said.
            let support = scores.filter { $0.score >= 0.5 }.count - 1
            if support > 0 { best.score = min(1, best.score + 0.05 * Double(min(2, support))) }
            found.append(best)
        }
        return LookReading(candidates: found)
    }

    // MARK: - Matching a name

    /// How well a line of text shows a name, from its shape alone.
    private static func match(_ name: [String], in line: [String]) -> (Double, LookCandidate.Evidence)? {
        guard line.count >= name.count,
              (0...(line.count - name.count)).contains(where: { Array(line[$0..<($0 + name.count)]) == name }) else { return nil }
        // The lead is folded like everything else: "TALK" is read as "taik" on both sides.
        for lead in badgeLeads where line == lead.flatMap(words) + name {
            return (1, .badge)
        }
        switch line.count - name.count {
        case 0: return (1, .title)
        case 1...3: return (0.85, .title)
        case 4...7: return (0.5, .mention)
        default: return (0.25, .mention)
        }
    }

    /// The words of a line as they are compared.
    ///
    /// A word with a capital inside it is two words: "FireFox" is "fire" and "fox", and
    /// so matches an assistant named Fire Fox. "Firefox", written the way the browser
    /// writes it, stays one word and does not. Letters that text recognition confuses on
    /// a screen are made the same: a capital I, a small L, and the digit one; the letter
    /// O and zero.
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var last: Character?
        func close() {
            if !current.isEmpty { words.append(current) }
            current = ""
        }
        for character in text {
            guard character.isLetter || character.isNumber else {
                close()
                last = nil
                continue
            }
            if let last, last.isLowercase, character.isUppercase { close() }
            current.append(folded(character))
            last = character
        }
        close()
        return words
    }

    private static func folded(_ character: Character) -> Character {
        switch character {
        case "l", "I", "1", "i", "L": return "i"
        case "0", "O", "o": return "o"
        default: return character.lowercased().first ?? character
        }
    }

    /// Whether one line of text sits directly over another, as two lines of one label do.
    private static func isAbove(_ upper: FrameBox, _ lower: FrameBox) -> Bool {
        let gap = lower.y - upper.maxY
        let overlap = min(upper.maxX, lower.maxX) - max(upper.x, lower.x)
        return upper.midY < lower.y && gap < 1.5 * lower.height && overlap > 0
    }

    // MARK: - Where it is

    /// How squarely the wearer is facing something in the frame, from 0.5 to 1.
    static func facing(_ box: FrameBox) -> Double {
        let across = min(1, abs(box.midX - 0.5) / 0.5)
        let down = min(1, abs(box.midY - 0.5) / 0.5)
        return 1 - 0.4 * across - 0.1 * down
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }
}

/// The code that marks an assistant's window: `PFX:BOT:INDY`.
///
/// It is short and in capitals so that it fits the smallest, coarsest QR code, which is
/// the one a camera can still read from across a desk.
enum LookMarker {
    static let lead = "PFX:BOT:"

    /// The text to put in a QR code for an assistant, or nil when its name has no letter
    /// or digit a QR code's compact alphabet can carry.
    static func payload(for name: String) -> String? {
        let kept = plain(name)
        return kept.isEmpty ? nil : lead + kept
    }

    /// Whether a code names this assistant, by any of its names.
    static func names(_ payload: String, _ entry: LookName) -> Bool {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard text.hasPrefix(lead) else { return false }
        let named = plain(String(text.dropFirst(lead.count)))
        guard !named.isEmpty else { return false }
        return entry.all.contains { plain($0) == named }
    }

    /// Capitals and digits only, with single spaces between words.
    private static func plain(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive], locale: nil).uppercased()
        let kept = folded.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : " "
        }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}
