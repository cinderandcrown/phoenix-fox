// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Notes left at a place: "leave a note here: breaker fourteen is the kitchen."
//
// A note is found again by standing where it was left. The notes and their coordinates
// are sealed on the phone and are not sent anywhere.

import Foundation

struct PlaceNote: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var text: String
    var latitude: Double
    var longitude: Double
    /// How sure the phone was of the position when the note was left, in meters.
    var accuracy: Double
    var at: Date
    /// When this note was last offered without being asked for.
    var offeredAt: Date?
}

struct PlaceNotes: Codable, Equatable, Sendable {
    private(set) var notes: [PlaceNote] = []

    static let limit = 200
    /// How close counts as "here", in meters, before the phone's own uncertainty is added.
    static let radius = 35.0
    /// The most uncertainty that is added to the radius. Indoors a fix can be off by a
    /// building's width, and a note should not be read out from across the street.
    static let slack = 60.0
    /// A position worse than this is not good enough to pin a note to.
    static let worstAccuracy = 150.0
    /// How long before the same note is offered again without being asked for.
    static let offerGap: TimeInterval = 4 * 3_600

    /// Adds a note. The oldest is dropped when the list is full.
    @discardableResult
    mutating func leave(_ text: String, latitude: Double, longitude: Double, accuracy: Double, id: UUID = UUID(), at: Date) -> PlaceNote {
        let note = PlaceNote(id: id, text: WorkshopText.sentence(text), latitude: latitude, longitude: longitude, accuracy: accuracy, at: at)
        notes.append(note)
        if notes.count > Self.limit { notes.removeFirst(notes.count - Self.limit) }
        return note
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> PlaceNote? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        return notes.remove(at: index)
    }

    /// The notes within reach of a position, nearest first.
    func near(latitude: Double, longitude: Double, accuracy: Double) -> [(note: PlaceNote, meters: Double)] {
        let reach = Self.radius + min(max(accuracy, 0), Self.slack)
        return notes
            .map { ($0, Self.meters(latitude, longitude, $0.latitude, $0.longitude)) }
            .filter { $0.1 <= reach + min($0.0.accuracy, Self.slack) / 2 }
            .sorted { $0.1 < $1.1 }
            .map { (note: $0.0, meters: $0.1) }
    }

    /// The notes to offer when the glasses are put on here, marked as offered. A note that
    /// was offered a short while ago is left out, so taking the glasses off and on at a
    /// desk does not repeat it.
    mutating func offer(latitude: Double, longitude: Double, accuracy: Double, now: Date) -> [PlaceNote] {
        let due = near(latitude: latitude, longitude: longitude, accuracy: accuracy)
            .map(\.note)
            .filter { note in
                // A note is not offered straight after it is left.
                guard now.timeIntervalSince(note.at) >= 15 * 60 else { return false }
                guard let offered = note.offeredAt else { return true }
                return now.timeIntervalSince(offered) >= Self.offerGap
            }
        for note in due {
            if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index].offeredAt = now }
        }
        return due
    }

    /// The distance between two positions in meters, by the haversine formula.
    static func meters(_ latitude1: Double, _ longitude1: Double, _ latitude2: Double, _ longitude2: Double) -> Double {
        let radius = 6_371_000.0
        let phi1 = latitude1 * .pi / 180
        let phi2 = latitude2 * .pi / 180
        let deltaPhi = (latitude2 - latitude1) * .pi / 180
        let deltaLambda = (longitude2 - longitude1) * .pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    // MARK: - Saying

    static func spoken(_ found: [PlaceNote], limit: Int = 4) -> String {
        switch found.count {
        case 0:
            return "There are no notes here."
        case 1:
            return "One note here: \(closed(found[0].text))"
        default:
            var parts = ["\(found.count) notes here."]
            for (index, note) in found.prefix(limit).enumerated() {
                parts.append("\(index + 1): \(closed(note.text))")
            }
            if found.count > limit { parts.append("And \(found.count - limit) more.") }
            return parts.joined(separator: " ")
        }
    }

    /// What is said when the glasses are put on where a note was left.
    static func spokenOffer(_ notes: [PlaceNote]) -> String? {
        guard let first = notes.first else { return nil }
        if notes.count == 1 { return "You left a note here: \(closed(first.text))" }
        return "You left \(notes.count) notes here. The nearest: \(closed(first.text)) Say \"any notes here\" for the rest."
    }

    private static func closed(_ text: String) -> String {
        guard let last = text.last else { return text }
        return ".!?".contains(last) ? text : text + "."
    }
}

/// What the workshop did today, kept so the day can be closed in one sentence.
///
/// Health records are never written here: the journal is what gets sent to an assistant.
struct WorkshopJournal: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case walkThrough, tally, placeNote, council, relay, skill, standingOrder
    }

    struct Entry: Codable, Equatable, Sendable {
        var kind: Kind
        var summary: String
        var at: Date
    }

    private(set) var entries: [Entry] = []

    static let keepDays = 14

    mutating func note(_ kind: Kind, _ summary: String, at: Date) {
        entries.append(Entry(kind: kind, summary: summary, at: at))
        let cutoff = at.addingTimeInterval(-Double(Self.keepDays) * 86_400)
        entries.removeAll { $0.at < cutoff }
    }

    func entries(on day: Date, calendar: Calendar) -> [Entry] {
        entries.filter { calendar.isDate($0.at, inSameDayAs: day) }
    }

    mutating func removeAll() {
        entries.removeAll()
    }
}

enum DaySheet {
    private static let order: [(kind: WorkshopJournal.Kind, title: String, spoken: String)] = [
        (.walkThrough, "Walk-throughs", "walk-through"),
        (.tally, "Counts", "count"),
        (.council, "Council votes", "council vote"),
        (.relay, "Work handed to the team", "relay"),
        (.skill, "Skills used", "skill"),
        (.placeNote, "Notes left at places", "place note"),
        (.standingOrder, "Standing orders that ran", "standing order"),
    ]

    /// The day's sheet in Markdown, or nil when nothing was recorded.
    static func compose(_ entries: [WorkshopJournal.Entry], day: Date, calendar: Calendar, locale: Locale = .current, limit: Int = 7_000) -> String? {
        guard !entries.isEmpty else { return nil }
        let date = WorkshopText.stamp(day, date: .full, time: .none, calendar: calendar, locale: locale)

        var lines = ["# Day sheet: \(date)"]
        var length = lines[0].count
        var left = 0
        for group in order {
            let rows = entries.filter { $0.kind == group.kind }
            guard !rows.isEmpty else { continue }
            var section = ["", "## \(group.title)"]
            for row in rows {
                section.append("- \(WorkshopText.clock(row.at, calendar: calendar, locale: locale)): \(row.summary)")
            }
            let size = section.reduce(0) { $0 + $1.count + 1 }
            if length + size > limit - 60 {
                left += rows.count
                continue
            }
            lines.append(contentsOf: section)
            length += size
        }
        if left > 0 {
            lines.append("")
            lines.append("\(WorkshopText.count(left, "more entry", "more entries")) did not fit in this message.")
        }
        return lines.joined(separator: "\n")
    }

    /// What the assistant is asked to do with the sheet.
    static func prompt(_ sheet: String) -> String {
        """
        This is my day sheet, written by my glasses from what I did today. File it. Then tell me, in three sentences at most, what stands out and what is still open.

        \(sheet)
        """
    }

    /// The day said aloud, from the phone alone: "Today: 2 walk-throughs, 1 count."
    static func spoken(_ entries: [WorkshopJournal.Entry]) -> String {
        guard !entries.isEmpty else { return "Nothing is recorded for today." }
        var parts: [String] = []
        for group in order {
            let count = entries.filter { $0.kind == group.kind }.count
            if count > 0 { parts.append(WorkshopText.count(count, group.spoken)) }
        }
        var line = "Today: \(WorkshopText.list(parts))."
        if let last = entries.last { line += " The last was: \(last.summary)" }
        return line
    }
}
