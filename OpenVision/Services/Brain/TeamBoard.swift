// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// What each assistant is doing, for the home screen.
//
// The board is filled from the two places the app already talks to the relay: an ask going
// out and coming back, and an alert arriving in the inbox. It adds no network calls. The
// relay does not report what an assistant does between an ask and its reply, so the board
// shows what the app knows first-hand and nothing it would have to guess.
//
// `TeamBoard` is the record and the wording. `TeamBoardStore` publishes it.

import Foundation

struct TeamBoard: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Nothing asked since the app started.
        case ready
        case working(task: String, since: Date)
        case answered(text: String, at: Date)
        /// The assistant sent something without being asked.
        case alerted(text: String, at: Date, urgent: Bool)
        case failed(reason: String, at: Date)
    }

    struct Event: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable {
            case asked
            case answered
            case alerted
            case failed

            /// The heading for this kind of event in an assistant's recent work.
            var label: String {
                switch self {
                case .asked: return "You asked"
                case .answered: return "Answered"
                case .alerted: return "Sent you"
                case .failed: return "No answer"
                }
            }
        }

        let id: Int
        let kind: Kind
        let text: String
        let at: Date
    }

    struct Member: Equatable, Sendable, Identifiable {
        let id: String
        var name: String
        var isDefault: Bool
        var status: Status = .ready
        /// The newest first.
        var events: [Event] = []

        var isWorking: Bool {
            if case .working = status { return true }
            return false
        }

        /// One or two letters for the avatar: "FF" for Fire Fox, "I" for Indy.
        var monogram: String {
            let letters = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).prefix(2).compactMap(\.first)
            return letters.isEmpty ? "?" : String(letters).uppercased()
        }
    }

    /// Events kept for each assistant.
    static let eventLimit = 12

    private(set) var members: [Member] = []
    private var nextEvent = 0

    init(roster: [AssistantBot] = []) {
        sync(roster: roster)
    }

    // MARK: - The roster

    /// Follows the roster in Settings. An assistant that is still there keeps its status.
    mutating func sync(roster: [AssistantBot]) {
        let known = Dictionary(members.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        members = AssistantRoster.normalized(roster).compactMap { bot in
            guard seen.insert(bot.id).inserted else { return nil }
            var member = known[bot.id] ?? Member(id: bot.id, name: bot.name, isDefault: bot.isDefault)
            member.name = bot.name
            member.isDefault = bot.isDefault
            return member
        }
    }

    /// The members a target names: one assistant, everyone, or the default when none is named.
    private func indices(for target: String?) -> [Int] {
        let name = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.compare(AssistantBot.allBots, options: .caseInsensitive) == .orderedSame {
            return Array(members.indices)
        }
        if !name.isEmpty {
            // A name the roster does not have is not put on someone else's card.
            return members.firstIndex { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }.map { [$0] } ?? []
        }
        return members.firstIndex(where: \.isDefault).map { [$0] } ?? []
    }

    private mutating func record(_ kind: Event.Kind, _ text: String, at: Date, on index: Int) {
        nextEvent += 1
        members[index].events.insert(Event(id: nextEvent, kind: kind, text: text, at: at), at: 0)
        if members[index].events.count > Self.eventLimit {
            members[index].events.removeLast(members[index].events.count - Self.eventLimit)
        }
    }

    // MARK: - What happened

    /// An ask went out.
    mutating func asked(_ target: String?, task: String, at: Date) {
        let task = Self.oneLine(task)
        for index in indices(for: target) {
            members[index].status = .working(task: task, since: at)
            record(.asked, task, at: at, on: index)
        }
    }

    /// A reply came back from `name`.
    mutating func answered(by name: String, text: String, at: Date) {
        let text = Self.oneLine(text)
        for index in indices(for: name.isEmpty ? nil : name) where !text.isEmpty {
            members[index].status = .answered(text: text, at: at)
            record(.answered, text, at: at, on: index)
        }
    }

    /// The ask to `target` is over. Anyone still marked as working did not answer.
    mutating func settled(_ target: String?, at: Date) {
        for index in indices(for: target) where members[index].isWorking {
            members[index].status = members[index].events.first { $0.kind != .asked }.map(Self.status(from:)) ?? .ready
        }
    }

    /// The ask to `target` failed.
    mutating func failed(_ target: String?, reason: String, at: Date) {
        let reason = Self.oneLine(reason)
        for index in indices(for: target) where members[index].isWorking {
            members[index].status = .failed(reason: reason, at: at)
            record(.failed, reason, at: at, on: index)
        }
    }

    /// An alert arrived from `name`. It does not replace work in progress.
    mutating func alerted(by name: String, text: String, urgent: Bool, at: Date) {
        let text = Self.oneLine(text)
        for index in indices(for: name.isEmpty ? nil : name) where !text.isEmpty {
            if !members[index].isWorking {
                members[index].status = .alerted(text: text, at: at, urgent: urgent)
            }
            record(.alerted, text, at: at, on: index)
        }
    }

    /// What a card goes back to when an ask is withdrawn: the last thing that was true.
    private static func status(from event: Event) -> Status {
        switch event.kind {
        case .answered: return .answered(text: event.text, at: event.at)
        case .alerted: return .alerted(text: event.text, at: event.at, urgent: false)
        case .failed: return .failed(reason: event.text, at: event.at)
        case .asked: return .ready
        }
    }

    // MARK: - Reading the board

    /// The assistant that has been waiting longest for its ask, for the live state.
    var working: Member? {
        members.filter(\.isWorking).min { since($0) < since($1) }
    }

    /// "Indy", "Indy and Rally", or "everyone", for whoever is working now.
    var workingNames: String? {
        let names = members.filter(\.isWorking).map(\.name)
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case members.count where names.count > 2: return "everyone"
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names.count) assistants"
        }
    }

    private func since(_ member: Member) -> Date {
        if case .working(_, let since) = member.status { return since }
        return .distantFuture
    }

    // MARK: - Words

    /// The line under an assistant's name.
    static func line(for status: Status, now: Date) -> String {
        switch status {
        case .ready:
            return "Ready"
        case .working(let task, _):
            return task.isEmpty ? "Working" : "Working on: \(short(task))"
        case .answered(let text, let at):
            return "Answered \(ago(at, now: now)): \(short(text))"
        case .alerted(let text, let at, let urgent):
            return "\(urgent ? "Urgent" : "Sent") \(ago(at, now: now)): \(short(text))"
        case .failed(let reason, let at):
            return "No answer \(ago(at, now: now)). \(short(reason))"
        }
    }

    /// What VoiceOver says for a card: the name, then the line, then how long it has worked.
    static func spoken(for member: Member, now: Date) -> String {
        var parts = [member.name, line(for: member.status, now: now)]
        if case .working(_, let since) = member.status {
            parts.append("for \(duration(now.timeIntervalSince(since)))")
        }
        return parts.joined(separator: ". ")
    }

    /// Something to say to reach this assistant. The default one needs no name.
    static func example(for member: Member, wakeWord: String) -> String {
        member.isDefault
            ? "“\(wakeWord), what should I do next?”"
            : "“\(wakeWord), ask \(member.name) to check on it.”"
    }

    /// Something to say to reach everyone at once.
    static func exampleForEveryone(wakeWord: String) -> String {
        "“\(wakeWord), all hands.”"
    }

    /// "just now", "2 minutes ago", "3 hours ago", "5 days ago".
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "just now" : "\(duration(seconds)) ago"
    }

    /// "20 seconds", "1 minute", "3 hours", "2 days".
    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds.rounded(.down)))
        func some(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s")" }
        switch seconds {
        case ..<60: return some(seconds, "second")
        case ..<3600: return some(seconds / 60, "minute")
        case ..<86_400: return some(seconds / 3600, "hour")
        default: return some(seconds / 86_400, "day")
        }
    }

    /// Text on a card is one line, so line breaks become spaces.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Cut at a word near `limit` characters. The card truncates what does not fit; this
    /// keeps VoiceOver from reading a whole report as a status.
    static func short(_ text: String, limit: Int = 120) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        let cut = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:.")) + "…"
    }
}
