// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Turns loose pieces of recognized text into the order a person would read them.
//
// A text recognizer returns fragments in no useful order: a two-column letter comes back
// with the columns interleaved line by line. Read aloud like that, it is noise. This file
// rebuilds columns, lines, and paragraphs from the positions alone, so it works the same
// for a sign, a receipt, or a page.

import Foundation

/// A rectangle in a camera frame. Each value runs from 0 to 1, and the origin is the top
/// left, so `y` grows downward the way a page is read.
struct FrameBox: Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
}

/// One run of text the recognizer found, usually a line or part of a line.
struct TextFragment: Equatable, Sendable {
    var text: String
    var box: FrameBox
    /// The recognizer's own confidence, from 0 to 1.
    var confidence: Double

    init(_ text: String, box: FrameBox, confidence: Double = 1) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

enum ReadingOrder {
    /// The text as paragraphs, in reading order.
    static func paragraphs(_ fragments: [TextFragment]) -> [String] {
        let kept = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !kept.isEmpty else { return [] }
        return blocks(kept, lineHeight: medianHeight(kept)).flatMap { paragraphs(inBlock: $0) }
    }

    /// The lines in reading order, each with its fragments joined. Used where the line
    /// breaks carry meaning, such as a medicine label.
    static func lines(_ fragments: [TextFragment]) -> [TextFragment] {
        let kept = fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !kept.isEmpty else { return [] }
        return blocks(kept, lineHeight: medianHeight(kept)).flatMap { block in
            rows(block).map(merge)
        }
    }

    /// Only the largest text in view: the words a sign is meant to be read by.
    static func headline(_ fragments: [TextFragment]) -> [String] {
        guard let tallest = fragments.map(\.box.height).max(), tallest > 0 else { return [] }
        return paragraphs(fragments.filter { $0.box.height >= tallest * 0.5 })
    }

    // MARK: - Blocks

    /// Splits the page into blocks that are each read top to bottom, in the order the
    /// blocks themselves are read. Columns split first, then wide vertical gaps.
    private static func blocks(_ fragments: [TextFragment], lineHeight: Double) -> [[TextFragment]] {
        if let (left, right) = columnSplit(fragments, lineHeight: lineHeight) {
            return blocks(left, lineHeight: lineHeight) + blocks(right, lineHeight: lineHeight)
        }
        if let (top, bottom) = rowSplit(fragments, lineHeight: lineHeight) {
            return blocks(top, lineHeight: lineHeight) + blocks(bottom, lineHeight: lineHeight)
        }
        return [fragments]
    }

    /// A column split needs a clear vertical gutter with at least two lines on each side.
    /// One line with a wide space in it, such as a price at the end of a receipt row, is
    /// not two columns.
    private static func columnSplit(_ fragments: [TextFragment], lineHeight: Double) -> ([TextFragment], [TextFragment])? {
        let spans = fragments.map { ($0.box.x, $0.box.maxX) }.sorted { $0.0 < $1.0 }
        var reach = spans[0].1
        var best: (gap: Double, at: Double)?
        for span in spans.dropFirst() {
            let gap = span.0 - reach
            if gap > (best?.gap ?? 0) { best = (gap, reach + gap / 2) }
            reach = max(reach, span.1)
        }
        guard let best, best.gap >= max(0.03, lineHeight * 1.5) else { return nil }
        let left = fragments.filter { $0.box.midX < best.at }
        let right = fragments.filter { $0.box.midX >= best.at }
        guard rows(left).count >= 2, rows(right).count >= 2 else { return nil }
        return (left, right)
    }

    /// Splits at the widest vertical gap when it is wider than a normal line break. When
    /// there is none, looks for a heading that sits across columns: the first line break
    /// below which the rest of the page divides into columns.
    private static func rowSplit(_ fragments: [TextFragment], lineHeight: Double) -> ([TextFragment], [TextFragment])? {
        let lines = rows(fragments)
        guard lines.count >= 2 else { return nil }
        var widest: (gap: Double, index: Int)?
        for index in 1..<lines.count {
            let above = lines[index - 1].map(\.box.maxY).max() ?? 0
            let below = lines[index].map(\.box.y).min() ?? 0
            let gap = below - above
            if gap > (widest?.gap ?? 0) { widest = (gap, index) }
        }
        if let widest, widest.gap >= lineHeight * 1.2 {
            return (Array(lines[..<widest.index].joined()), Array(lines[widest.index...].joined()))
        }
        for index in 1..<lines.count {
            let below = Array(lines[index...].joined())
            if columnSplit(below, lineHeight: lineHeight) != nil {
                return (Array(lines[..<index].joined()), below)
            }
        }
        return nil
    }

    // MARK: - Lines and paragraphs

    /// Groups fragments into rows by vertical overlap, top to bottom, each row left to right.
    private static func rows(_ fragments: [TextFragment]) -> [[TextFragment]] {
        var rows: [[TextFragment]] = []
        for fragment in fragments.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last, let anchor = last.first,
               abs(anchor.box.midY - fragment.box.midY) < min(anchor.box.height, fragment.box.height) * 0.6 {
                rows[rows.count - 1].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { $0.sorted { $0.box.x < $1.box.x } }
    }

    private static func merge(_ row: [TextFragment]) -> TextFragment {
        let text = row.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        let minX = row.map(\.box.x).min() ?? 0
        let minY = row.map(\.box.y).min() ?? 0
        let maxX = row.map(\.box.maxX).max() ?? 0
        let maxY = row.map(\.box.maxY).max() ?? 0
        let box = FrameBox(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return TextFragment(text, box: box, confidence: row.map(\.confidence).min() ?? 0)
    }

    private static func paragraphs(inBlock block: [TextFragment]) -> [String] {
        let lines = rows(block).map(merge)
        var paragraphs: [String] = []
        var current = ""
        var previous: TextFragment?
        for line in lines {
            if let previous, line.box.y - previous.box.maxY > previous.box.height * 0.9, !current.isEmpty {
                paragraphs.append(current)
                current = ""
            }
            current = join(current, line.text)
            previous = line
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs
    }

    /// Joins a wrapped line to the text before it. A word broken with a hyphen at the end
    /// of a line is put back together.
    private static func join(_ text: String, _ next: String) -> String {
        guard !text.isEmpty else { return next }
        if text.hasSuffix("-"), let before = text.dropLast().last, before.isLetter,
           let first = next.first, first.isLowercase {
            return String(text.dropLast()) + next
        }
        return text + " " + next
    }

    private static func medianHeight(_ fragments: [TextFragment]) -> Double {
        let heights = fragments.map(\.box.height).sorted()
        return heights[heights.count / 2]
    }
}

/// Reads long text a part at a time, so the wearer can stop, go back, or hear a part again.
struct ReadingSession: Equatable, Sendable {
    private(set) var parts: [String]
    private(set) var index = 0

    /// - Parameter wordsPerPart: About how much is spoken before pausing for "read more".
    init(paragraphs: [String], wordsPerPart: Int = 60) {
        parts = Self.split(paragraphs, limit: max(10, wordsPerPart))
    }

    var isEmpty: Bool { parts.isEmpty }
    var hasMore: Bool { index + 1 < parts.count }

    /// The part at the cursor, with a note about what is left.
    var spoken: String {
        guard !parts.isEmpty else { return "" }
        if parts.count == 1 { return parts[0] }
        let tail = hasMore ? " Say read more to continue." : " That's the end."
        return "Part \(index + 1) of \(parts.count). \(parts[index])\(tail)"
    }

    /// Moves forward. Returns false at the end.
    mutating func advance() -> Bool {
        guard hasMore else { return false }
        index += 1
        return true
    }

    /// Moves back. Returns false at the start.
    mutating func goBack() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        return true
    }

    /// Packs whole sentences into parts no longer than the limit. A sentence longer than
    /// the limit becomes its own part, so nothing is cut mid-sentence.
    private static func split(_ paragraphs: [String], limit: Int) -> [String] {
        var parts: [String] = []
        var current: [String] = []
        var count = 0
        for sentence in paragraphs.flatMap(sentences) {
            let words = sentence.split(separator: " ").count
            if count > 0, count + words > limit {
                parts.append(current.joined(separator: " "))
                current = []
                count = 0
            }
            current.append(sentence)
            count += words
        }
        if !current.isEmpty { parts.append(current.joined(separator: " ")) }
        return parts
    }

    private static func sentences(_ paragraph: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let characters = Array(paragraph)
        for (offset, character) in characters.enumerated() {
            current.append(character)
            let endsSentence = ".!?".contains(character)
            let nextIsSpace = offset + 1 < characters.count && characters[offset + 1] == " "
            if endsSentence && (nextIsSpace || offset + 1 == characters.count) {
                sentences.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }
}
