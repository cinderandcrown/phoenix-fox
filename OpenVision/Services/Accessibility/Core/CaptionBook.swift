// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Holds live captions: the line still being spoken, and the finished lines before it.
//
// The speech recognizer keeps revising one ever-growing piece of text. Captions are easier
// to follow as short lines that stop changing once the speaker pauses, so this file cuts
// the stream into lines, keeps a bounded history for "what did I miss?", and writes a
// plain transcript when the wearer asks to keep the conversation.

import Foundation

struct CaptionLine: Equatable, Codable, Sendable, Identifiable {
    var id: Int
    var at: Date
    var text: String
}

struct CaptionBook: Sendable {
    /// Finished lines, oldest first.
    private(set) var lines: [CaptionLine] = []
    /// The line being spoken now. It may still change.
    private(set) var live = ""
    private var liveStarted: Date?
    private var lastChange: Date?
    private var nextID = 0
    /// How many words of the recognizer's current session are already in finished lines.
    private var closedWords = 0
    private var sessionWords = 0

    /// A pause this long ends the line.
    var pause: TimeInterval = 1.4
    /// A line longer than this is ended at a word, so it fits a phone screen or a lens.
    var maxCharacters = 120
    /// The most finished lines kept in memory.
    var capacity = 400

    init() {}

    /// Takes everything the recognizer has for its current session. The recognizer keeps
    /// one growing text per session; words already closed into lines are skipped, so only
    /// the words after them form the line in progress.
    mutating func update(_ sessionText: String, at now: Date) {
        let words = sessionText.split(whereSeparator: \.isWhitespace)
        // The recognizer revised its text to be shorter than what was already closed.
        if words.count < closedWords { closedWords = words.count }
        sessionWords = words.count
        let text = words[closedWords...].joined(separator: " ")
        guard text != live else { return }
        if live.isEmpty { liveStarted = now }
        live = text
        lastChange = now
        if live.count >= maxCharacters { commit(at: now) }
    }

    /// Passes over everything the recognizer has so far, without captioning it. Used while
    /// Phoenix Fox itself is speaking, so its own voice does not appear as a caption.
    mutating func skip(_ sessionText: String, at now: Date) {
        commit(at: now)
        sessionWords = sessionText.split(whereSeparator: \.isWhitespace).count
        closedWords = sessionWords
    }

    /// Call on a timer. Ends the line when the speaker has paused.
    mutating func tick(at now: Date) {
        guard !live.isEmpty, let lastChange, now.timeIntervalSince(lastChange) >= pause else { return }
        commit(at: now)
    }

    /// The recognizer ended its session. The next one starts its text from nothing.
    mutating func sessionEnded(at now: Date) {
        commit(at: now)
        closedWords = 0
        sessionWords = 0
    }

    /// Ends the line in progress, whatever its length.
    mutating func commit(at now: Date) {
        guard !live.isEmpty else { return }
        lines.append(CaptionLine(id: nextID, at: liveStarted ?? now, text: live))
        nextID += 1
        closedWords += live.split(whereSeparator: \.isWhitespace).count
        live = ""
        liveStarted = nil
        lastChange = nil
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    mutating func clear() {
        lines.removeAll()
        live = ""
        liveStarted = nil
        lastChange = nil
        // The recognizer's session goes on, so its words so far stay skipped.
        closedWords = sessionWords
    }

    /// What was said in the last stretch of time, oldest first, including the open line.
    func recent(seconds: TimeInterval, now: Date) -> [String] {
        var texts = lines.filter { now.timeIntervalSince($0.at) <= seconds }.map(\.text)
        if !live.isEmpty { texts.append(live) }
        return texts
    }

    /// The last lines that fit a small display, newest last.
    func tail(lines count: Int, charactersPerLine: Int) -> [String] {
        var all = lines.map(\.text)
        if !live.isEmpty { all.append(live) }
        let wrapped = all.suffix(count).flatMap { Self.wrap($0, width: charactersPerLine) }
        return Array(wrapped.suffix(count))
    }

    /// A plain-text transcript with the time each line began.
    func transcript(timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return lines.map { "[\(formatter.string(from: $0.at))] \($0.text)" }.joined(separator: "\n")
    }

    static func wrap(_ text: String, width: Int) -> [String] {
        var rows: [String] = []
        var row = ""
        for word in text.split(separator: " ") {
            if !row.isEmpty, row.count + 1 + word.count > width {
                rows.append(row)
                row = ""
            }
            row += row.isEmpty ? String(word) : " " + word
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}
