// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Standing orders: "whenever I put my glasses on, ask Fire Fox for my brief."
//
// The glasses report when they are put on, taken off, and how much battery is left. A
// standing order joins one of those, or a time of day, to something Jarvis says or asks
// an assistant. Every order has a cooldown, so glasses pushed up onto the head and back
// down a dozen times do not send a dozen requests.

import Foundation

struct StandingOrder: Codable, Equatable, Identifiable, Sendable {
    enum Trigger: Codable, Equatable, Sendable {
        case putOn
        case takenOff
        /// The battery of the glasses is at or below this percentage.
        case batteryBelow(Int)
        /// Minutes after midnight, every day.
        case timeOfDay(Int)
    }

    enum Action: Codable, Equatable, Sendable {
        case say(String)
        /// `bot` is an assistant's name, or nil for the wearer's default assistant.
        case ask(bot: String?, text: String)
    }

    var id: UUID
    var trigger: Trigger
    var action: Action
    var enabled = true
    var lastFired: Date?
    /// For battery orders: false after firing, until the battery has been charged again.
    var armed = true

    init(id: UUID = UUID(), trigger: Trigger, action: Action) {
        self.id = id
        self.trigger = trigger
        self.action = action
    }

    /// The order in words, for the list in Settings and for reading back.
    var summary: String {
        let when: String
        switch trigger {
        case .putOn: when = "When the glasses go on"
        case .takenOff: when = "When the glasses come off"
        case .batteryBelow(let level): when = "When the battery is below \(level) percent"
        case .timeOfDay(let minutes): when = "Every day at \(StandingOrders.clock(minutes))"
        }
        switch action {
        case .say(let text): return "\(when), say: \(text)"
        case .ask(let bot, let text): return "\(when), ask \(bot ?? "your assistant"): \(text)"
        }
    }
}

enum StandingOrders {
    /// The most orders kept. Each one can spend a request several times a day.
    static let limit = 10
    /// The shortest time between two firings of a put-on or take-off order.
    static let cooldown: TimeInterval = 30 * 60
    /// How late a time-of-day order may still fire, when the app was not running on the minute.
    static let lateWindow = 20
    /// How far the battery must rise above an order's level before the order can fire again.
    static let rearmMargin = 5

    enum Event: Equatable, Sendable {
        case putOn
        case takenOff
        case battery(Int)
        /// The clock moved on. Sent about once a minute while the app runs.
        case tick
    }

    /// Works out which orders fire for an event, and marks them as fired.
    static func fire(_ event: Event, orders: inout [StandingOrder], now: Date, calendar: Calendar) -> [StandingOrder] {
        var fired: [StandingOrder] = []
        for index in orders.indices {
            var order = orders[index]
            defer { orders[index] = order }
            switch (order.trigger, event) {
            case (.putOn, .putOn), (.takenOff, .takenOff):
                guard order.enabled, cooled(order, now: now) else { continue }
            case (.batteryBelow(let level), .battery(let reading)):
                if reading >= level + rearmMargin { order.armed = true }
                guard order.enabled, order.armed, reading <= level else { continue }
                order.armed = false
            case (.timeOfDay(let minutes), .tick):
                let parts = calendar.dateComponents([.hour, .minute], from: now)
                let minuteNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                guard order.enabled, (minutes...(minutes + lateWindow)).contains(minuteNow) else { continue }
                if let last = order.lastFired, calendar.isDate(last, inSameDayAs: now) { continue }
            default:
                continue
            }
            order.lastFired = now
            fired.append(order)
        }
        return fired
    }

    private static func cooled(_ order: StandingOrder, now: Date) -> Bool {
        guard let last = order.lastFired else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    // MARK: - Spoken orders

    /// Reads a spoken order. Returns nil when the sentence is not one.
    ///
    /// - Parameter bots: The names of the wearer's assistants.
    static func parse(_ utterance: String, bots: [String]) -> StandingOrder? {
        var text = WorkshopText.command(utterance)
        var marked = false
        for lead in ["standing order ", "new standing order ", "whenever ", "every time ", "each time ", "when "] where text.hasPrefix(lead) {
            text = String(text.dropFirst(lead.count))
            // "when" alone starts too many ordinary sentences to count as a mark.
            marked = lead != "when "
            break
        }
        guard let (trigger, rest) = trigger(in: text, marked: marked) else { return nil }
        guard let action = action(in: rest, bots: bots) else { return nil }
        return StandingOrder(trigger: trigger, action: action)
    }

    private static let putOnPhrases = [
        "i put my glasses on", "i put the glasses on", "i put on my glasses", "i put on the glasses", "i put them on",
        "i put these on", "my glasses go on", "the glasses go on", "i wear my glasses", "i start wearing my glasses",
    ]
    private static let takeOffPhrases = [
        "i take my glasses off", "i take the glasses off", "i take off my glasses", "i take off the glasses",
        "i take them off", "i take these off", "my glasses come off", "the glasses come off",
    ]
    private static let batteryPhrases = [
        "the battery is below", "the battery drops below", "the battery falls below", "the battery gets below",
        "the battery goes below", "the battery is under", "the battery drops under", "my battery is below",
        "my battery drops below", "battery is below", "battery drops below", "the battery is at or below",
        "the battery is less than", "the battery gets to", "the battery hits",
    ]
    private static let dailyPhrases: [(phrase: String, afternoon: Bool)] = [
        ("every day at", false), ("each day at", false), ("every morning at", false), ("daily at", false),
        ("every afternoon at", true), ("every evening at", true), ("every night at", true),
    ]

    private static func trigger(in text: String, marked: Bool) -> (StandingOrder.Trigger, String)? {
        if let rest = WorkshopText.after(text, putOnPhrases) { return (.putOn, rest) }
        if let rest = WorkshopText.after(text, takeOffPhrases) { return (.takenOff, rest) }
        if let rest = WorkshopText.after(text, batteryPhrases) {
            let words = rest.split(separator: " ").map(String.init)
            guard let level = SpokenNumber.leading(words), (1...99).contains(level.value) else { return nil }
            var used = level.used
            if used < words.count, words[used] == "percent" { used += 1 }
            return (.batteryBelow(level.value), words.dropFirst(used).joined(separator: " "))
        }
        for daily in dailyPhrases {
            guard let rest = WorkshopText.after(text, [daily.phrase]) else { continue }
            let words = rest.split(separator: " ").map(String.init)
            guard let time = time(words, afternoon: daily.afternoon) else { return nil }
            return (.timeOfDay(time.minutes), words.dropFirst(time.used).joined(separator: " "))
        }
        // "at 8 am every day …", only when the sentence was marked as an order.
        if marked, let rest = WorkshopText.after(text, ["at"]) {
            let words = rest.split(separator: " ").map(String.init)
            guard let time = time(words, afternoon: false) else { return nil }
            let after = words.dropFirst(time.used).joined(separator: " ")
            if let rest = WorkshopText.after(after, ["every day", "each day", "daily"]) {
                return (.timeOfDay(time.minutes), rest)
            }
        }
        return nil
    }

    /// A time of day at the start of `words`: "8", "8 30", "8 am", "5 30 p m", "noon".
    static func time(_ words: [String], afternoon: Bool) -> (minutes: Int, used: Int)? {
        guard let first = words.first else { return nil }
        if first == "noon" || first == "midday" { return (12 * 60, 1) }
        if first == "midnight" { return (0, 1) }
        guard let hour = SpokenNumber.leading(words), hour.value <= 2_359 else { return nil }
        var hours = hour.value
        var minutes = 0
        var used = hour.used
        if hours >= 100 {
            // "830" and "1730", as the recognizer sometimes writes a time.
            minutes = hours % 100
            hours /= 100
        } else if used < words.count, let minute = SpokenNumber.leading(Array(words[used...])),
                  (0...59).contains(minute.value) {
            minutes = minute.value
            used += minute.used
        }
        if used < words.count, ["o'clock", "oclock"].contains(words[used]) { used += 1 }
        guard (0...23).contains(hours), (0...59).contains(minutes) else { return nil }

        var meridiem: String?
        if used < words.count, ["am", "pm"].contains(words[used]) {
            meridiem = words[used]
            used += 1
        } else if used + 1 < words.count, ["a", "p"].contains(words[used]), words[used + 1] == "m" {
            meridiem = words[used] + "m"
            used += 2
        }
        switch meridiem {
        case "pm" where hours < 12: hours += 12
        case "am" where hours == 12: hours = 0
        case nil where afternoon && hours < 12: hours += 12
        default: break
        }
        return (hours * 60 + minutes, used)
    }

    private static func action(in said: String, bots: [String]) -> StandingOrder.Action? {
        var rest = said
        for filler in ["then ", "please ", "i want you to ", "you should "] where rest.hasPrefix(filler) {
            rest = String(rest.dropFirst(filler.count))
        }
        guard !rest.isEmpty else { return nil }
        if let line = WorkshopText.after(rest, ["say", "tell me", "remind me to", "remind me"]), !line.isEmpty {
            let reminder = rest.hasPrefix("remind me")
            return .say(WorkshopText.sentence(reminder ? "Reminder: \(line)" : line))
        }
        // The assistant's name, longest first so "Fire Fox" is not read as "Fire".
        for bot in bots.sorted(by: { $0.count > $1.count }) {
            let name = WorkshopText.words(bot).joined(separator: " ")
            guard !name.isEmpty else { continue }
            let leads = ["ask \(name) to", "ask \(name) for", "ask \(name)", "tell \(name) to", "tell \(name) that",
                         "tell \(name)", "have \(name)", "get \(name) to"]
            for lead in leads {
                guard let body = WorkshopText.after(rest, [lead]), !body.isEmpty else { continue }
                // "ask Indy for my brief" keeps "for": the assistant gets "For my brief" otherwise.
                let text = lead.hasSuffix(" for") ? "Give me \(body)" : WorkshopText.sentence(body)
                return .ask(bot: bot, text: text)
            }
        }
        if let body = WorkshopText.after(rest, ["ask for", "get me", "give me", "ask"]), !body.isEmpty {
            return .ask(bot: nil, text: rest.hasPrefix("ask ") && !rest.hasPrefix("ask for ") ? WorkshopText.sentence(body) : "Give me \(body)")
        }
        return nil
    }

    static func clock(_ minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let shown = hour % 12 == 0 ? 12 : hour % 12
        let half = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(shown) \(half)" : "\(shown):\(minute < 10 ? "0" : "")\(minute) \(half)"
    }
}
