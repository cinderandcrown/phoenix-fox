// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// A walk-through: a site, a room, or a vehicle inspected by walking and talking.
//
// "Note", "flag", and "photo" add items as the wearer goes. The list is built on the
// phone with no model, so a forty-item walk costs nothing until the report is sent, and
// then it costs one request.

import Foundation

struct WalkThrough: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case note
        /// Something that needs doing. Flags lead the report.
        case flag
    }

    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: UUID
        var kind: Kind
        var text: String
        var at: Date
        /// The name of the sealed picture kept with this item, if one was taken.
        var photo: String?
    }

    var id: UUID
    var name: String
    var startedAt: Date
    var finishedAt: Date?
    private(set) var items: [Item] = []

    /// The most items one walk-through holds.
    static let itemLimit = 200
    /// The longest report sent to an assistant. The relay refuses text past 8,000 characters.
    static let reportLimit = 7_000

    init(id: UUID = UUID(), name: String, startedAt: Date) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
    }

    var flags: [Item] { items.filter { $0.kind == .flag } }
    var photos: [String] { items.compactMap(\.photo) }
    var isFull: Bool { items.count >= Self.itemLimit }

    /// Adds an item. Returns nil when the walk-through is full.
    @discardableResult
    mutating func add(_ kind: Kind, _ text: String, photo: String? = nil, id: UUID = UUID(), at: Date) -> Item? {
        guard !isFull else { return nil }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = Item(
            id: id,
            kind: kind,
            text: words.isEmpty ? (photo == nil ? "No description" : "Photo") : WorkshopText.sentence(words),
            at: at,
            photo: photo
        )
        items.append(item)
        return item
    }

    /// Takes off the last item and returns it, so its picture can be removed too.
    mutating func removeLast() -> Item? {
        items.popLast()
    }

    // MARK: - Saying

    /// What is said after an item is added: "Flag 3."
    func spokenAck(for item: Item) -> String {
        let number = items.count
        switch (item.kind, item.photo != nil) {
        case (.flag, true): return "Flag \(number), with a photo."
        case (.flag, false): return "Flag \(number)."
        case (.note, true): return "Note \(number), with a photo."
        case (.note, false): return "Note \(number)."
        }
    }

    var spokenCounts: String {
        guard !items.isEmpty else { return "nothing noted" }
        var parts = [WorkshopText.count(items.count, "item")]
        if !flags.isEmpty { parts.append(WorkshopText.count(flags.count, "flag")) }
        if !photos.isEmpty { parts.append(WorkshopText.count(photos.count, "photo")) }
        return WorkshopText.list(parts)
    }

    /// The list read back. Flags come first, and a long list is cut short.
    func spokenSummary(limit: Int = 8) -> String {
        guard !items.isEmpty else { return "The \(name) walk-through has nothing in it yet." }
        let ordered = flags + items.filter { $0.kind == .note }
        var parts = ["\(WorkshopText.sentence(name)): \(spokenCounts)."]
        for item in ordered.prefix(limit) {
            parts.append((item.kind == .flag ? "Flag: " : "Note: ") + Self.closed(item.text))
        }
        if ordered.count > limit { parts.append("And \(ordered.count - limit) more.") }
        return parts.joined(separator: " ")
    }

    // MARK: - The report

    /// The most photos sent with one report. The relay has a size limit for a whole
    /// message, and past this many each picture would be too small to be worth sending.
    static let photoLimit = 12

    /// The items whose photos go with the report, in the order they are sent: flags
    /// first, because those are the pictures someone has to act on.
    func photosToSend(limit: Int = WalkThrough.photoLimit) -> [Item] {
        let withPhotos = items.filter { $0.photo != nil }
        let ordered = withPhotos.filter { $0.kind == .flag } + withPhotos.filter { $0.kind == .note }
        return Array(ordered.prefix(limit))
    }

    /// The report in Markdown. Photos are numbered in the order they are sent with it.
    ///
    /// - Parameters:
    ///   - sent: The items whose photos go with the report, in order. Left out, every
    ///     photo is numbered in the order it was taken.
    ///   - limit: The longest text allowed. Items that do not fit are counted in a last
    ///     line, never dropped silently.
    func report(sent: [Item]? = nil, calendar: Calendar = .current, locale: Locale = .current, limit: Int = .max) -> String {
        func clock(_ date: Date) -> String { WorkshopText.clock(date, calendar: calendar, locale: locale) }
        let started = WorkshopText.stamp(startedAt, date: .medium, time: .short, calendar: calendar, locale: locale)

        var head = ["# Walk-through: \(name)", ""]
        var when = "Started \(started)."
        if let finishedAt { when += " Finished \(clock(finishedAt))." }
        head.append(when)
        head.append("\(WorkshopText.sentence(spokenCounts)).")

        var photoNumber: [UUID: Int] = [:]
        for item in sent ?? items.filter({ $0.photo != nil }) {
            photoNumber[item.id] = photoNumber.count + 1
        }
        func row(_ item: Item) -> String {
            var text = "- \(clock(item.at)): \(Self.closed(item.text))"
            if let number = photoNumber[item.id] {
                text += " (photo \(number))"
            } else if item.photo != nil {
                text += " (photo kept on the phone)"
            }
            return text
        }

        var body: [String] = []
        if !flags.isEmpty {
            body.append("")
            body.append("## Needs attention")
            body.append(contentsOf: flags.map(row))
        }
        let notes = items.filter { $0.kind == .note }
        if !notes.isEmpty {
            body.append("")
            body.append("## Notes")
            body.append(contentsOf: notes.map(row))
        }

        var lines = head
        var length = head.joined(separator: "\n").count
        var left = body.filter { $0.hasPrefix("- ") }.count
        for line in body {
            // Room is kept for the line that says how many were left out.
            guard length + line.count + 1 <= limit - 60 else { break }
            lines.append(line)
            length += line.count + 1
            if line.hasPrefix("- ") { left -= 1 }
        }
        if left > 0 {
            lines.append("")
            lines.append("\(WorkshopText.count(left, "more item")) did not fit in this message.")
        }
        return lines.joined(separator: "\n")
    }

    private static func closed(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }
}
