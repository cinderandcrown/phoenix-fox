// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// A count kept by voice: "twelve cases of cups", "minus two lids".
//
// Both hands are on the stock, so every change is said back with the new total for that
// item. A wrong number is heard at once and "undo" takes it out. Nothing here uses a
// model or the network: the count is arithmetic.

import Foundation

struct Tally: Codable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable {
        /// The item as it was first said.
        var item: String
        var count: Int
    }

    /// One change, kept so it can be undone.
    struct Change: Codable, Equatable, Sendable {
        var item: String
        var before: Int?
        var after: Int
    }

    var name: String
    var startedAt: Date
    var finishedAt: Date?
    private(set) var lines: [Line] = []
    private(set) var changes: [Change] = []

    /// The most items one tally holds. Past this it is a spreadsheet.
    static let itemLimit = 300
    private static let undoDepth = 20

    init(name: String, startedAt: Date) {
        self.name = name
        self.startedAt = startedAt
    }

    var total: Int { lines.reduce(0) { $0 + $1.count } }
    var isEmpty: Bool { lines.isEmpty }

    /// Adds to an item, or takes away when `delta` is negative. A count never goes below
    /// zero. Returns the item's line afterwards, or nil when the tally is full.
    @discardableResult
    mutating func add(_ delta: Int, of item: String) -> Line? {
        change(item) { max(0, min(SpokenNumber.limit * 10, $0 + delta)) }
    }

    /// Replaces an item's count.
    @discardableResult
    mutating func set(_ count: Int, of item: String) -> Line? {
        change(item) { _ in max(0, count) }
    }

    func count(of item: String) -> Line? {
        let key = Self.key(item)
        return lines.first { Self.key($0.item) == key }
    }

    /// Takes back the last change. Returns it, or nil when there is nothing to undo.
    mutating func undo() -> Change? {
        guard let last = changes.popLast() else { return nil }
        let key = Self.key(last.item)
        guard let index = lines.firstIndex(where: { Self.key($0.item) == key }) else { return last }
        if let before = last.before {
            lines[index].count = before
        } else {
            lines.remove(at: index)
        }
        return last
    }

    private mutating func change(_ item: String, _ update: (Int) -> Int) -> Line? {
        let said = item.trimmingCharacters(in: .whitespaces)
        let key = Self.key(said)
        guard !key.isEmpty else { return nil }
        let line: Line
        if let index = lines.firstIndex(where: { Self.key($0.item) == key }) {
            let before = lines[index].count
            lines[index].count = update(before)
            changes.append(Change(item: lines[index].item, before: before, after: lines[index].count))
            line = lines[index]
        } else {
            guard lines.count < Self.itemLimit else { return nil }
            line = Line(item: said, count: update(0))
            lines.append(line)
            changes.append(Change(item: said, before: nil, after: line.count))
        }
        if changes.count > Self.undoDepth { changes.removeFirst(changes.count - Self.undoDepth) }
        return line
    }

    // MARK: - Matching items

    /// What makes two spoken items the same line: "case of cups" and "cases of cups" are.
    static func key(_ item: String) -> String {
        WorkshopText.words(item)
            .filter { !["the", "a", "an", "of"].contains($0) }
            .map(singular)
            .joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }
        for ending in ["sses", "shes", "ches", "xes", "zes"] where word.hasSuffix(ending) {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is") {
            return String(word.dropLast())
        }
        return word
    }

    // MARK: - Saying and sending

    /// The line said after a change: "Cups, 12."
    static func spoken(_ line: Line) -> String {
        "\(WorkshopText.sentence(line.item)), \(line.count)."
    }

    /// The whole count, read aloud. Long counts give the first items and the totals.
    func spokenSummary(limit: Int = 12) -> String {
        guard !lines.isEmpty else { return "The \(name) tally is empty." }
        var parts = lines.prefix(limit).map(Self.spoken)
        if lines.count > limit {
            parts.append("And \(WorkshopText.count(lines.count - limit, "more item")).")
        }
        parts.append("\(WorkshopText.count(lines.count, "item")), \(total) in all.")
        return parts.joined(separator: " ")
    }

    /// The count as a sheet, for an assistant or a spreadsheet.
    func csv() -> String {
        var rows = ["item,count"]
        for line in lines {
            rows.append("\(Self.field(line.item)),\(line.count)")
        }
        rows.append("total,\(total)")
        return rows.joined(separator: "\n")
    }

    /// One field, quoted when it has a comma, a quote, or a line break in it. A leading
    /// character a spreadsheet would run as a formula is held back with an apostrophe.
    private static func field(_ text: String) -> String {
        var value = text
        if let first = value.first, "=+-@".contains(first) { value = "'" + value }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
