// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - FastModeRouter.swift
// Rules decide the route, on the phone, before any model is paid for.
// Only task-like turns go to the relay. Short talk stays on the cheap instant brain.

import Foundation

struct RelayTurn: Equatable {
    var intent: String
    var targetBot: String
    var text: String
    var photo: Bool
    var clip: Bool
    var cacheable: Bool
}

enum JarvisRoute: Equatable {
    case instant(text: String, photo: Bool, cacheable: Bool)
    case relay(RelayTurn)
    case dictate(kind: String)
    case needsPro(String)
    case mind(MindCommand)
}

enum FastModeRouter {
    struct Context {
        var fastMode: Bool
        /// Whether the plan covers more than one assistant. See `PaidFeature.botTeam`.
        var isPro: Bool
        var bots: [AssistantBot]
        var instantReady: Bool
        var clipEnabled: Bool
        /// The assistant chosen by looking at its window. See `LookToTalk`. While one is
        /// held, a request that names nobody goes to it, and through the relay: the
        /// wearer is talking to that assistant, not to the quick model on the phone.
        var focus: String?

        init(fastMode: Bool, isPro: Bool, bots: [AssistantBot], instantReady: Bool, clipEnabled: Bool, focus: String? = nil) {
            self.fastMode = fastMode
            self.isPro = isPro
            self.bots = bots
            self.instantReady = instantReady
            self.clipEnabled = clipEnabled
            self.focus = focus
        }
    }

    /// The held assistant, when it is on the roster and the plan covers it. A name said
    /// aloud still wins: "ask Driver" goes to Driver whoever is being looked at.
    static func focus(in context: Context) -> AssistantBot? {
        guard let name = context.focus?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
              let bot = AssistantRoster.normalized(context.bots)
                  .first(where: { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }) else { return nil }
        return bot.isDefault || context.isPro ? bot : nil
    }

    static func rules(_ text: String, context: Context) -> JarvisRoute {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let held = focus(in: context)
        let fallback = held?.name ?? AssistantRoster.defaultBot(in: context.bots).name
        let instant = context.fastMode && context.instantReady && held == nil

        if let mind = mind(lower, bots: context.bots) { return .mind(mind) }

        if contains(lower, ["status report", "all hands", "everyone check in", "everyone report"]) {
            guard context.isPro else { return .needsPro(PaidFeature.botTeam.refusal) }
            return .relay(RelayTurn(intent: "status", targetBot: AssistantBot.allBots, text: text, photo: false, clip: false, cacheable: false))
        }
        if contains(lower, ["brief me", "morning digest", "what's my day", "whats my day", "daily briefing"]) {
            return .relay(RelayTurn(intent: "briefing", targetBot: fallback, text: text, photo: false, clip: false, cacheable: false))
        }
        if let dictation = dictation(lower, original: text, target: fallback) { return dictation }
        if contains(lower, ["look at this", "look at that", "take a look"]) {
            return .relay(RelayTurn(intent: "look", targetBot: fallback, text: text, photo: true, clip: context.clipEnabled, cacheable: false))
        }

        let visual = contains(lower, ["what am i looking at", "what is this", "what's this", "whats this", "translate this", "what does this say", "what do you see"])
        if visual {
            if instant {
                return .instant(text: text, photo: true, cacheable: false)
            }
            return .relay(RelayTurn(intent: "look", targetBot: fallback, text: text, photo: true, clip: false, cacheable: false))
        }

        let addressed = AssistantRoster.address(in: text, bots: context.bots)
        if addressed.explicit && !addressed.bot.isDefault && !context.isPro {
            return .needsPro(PaidFeature.botTeam.refusal)
        }
        let target = addressed.explicit ? addressed.bot.name : fallback
        let body = addressed.remainder

        if isTask(body.lowercased()) || (addressed.explicit && !addressed.bot.isDefault) {
            return .relay(RelayTurn(intent: "message", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
        }
        if instant {
            return .instant(text: body, photo: false, cacheable: true)
        }
        return .relay(RelayTurn(intent: "message", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
    }

    private static func mind(_ lower: String, bots: [AssistantBot]) -> MindCommand? {
        if lower == "mind meld on" || lower == "start mind meld" || lower == "turn mind meld on" {
            return .consent(true)
        }
        if lower == "mind meld off" || lower == "stop mind meld" || lower == "turn mind meld off" {
            return .consent(false)
        }
        if lower == "what should i do" || lower == "what do i need" || lower == "what's next" || lower == "whats next" || lower == "anticipate" {
            return .anticipate
        }
        if lower == "what did i just say" || lower == "what was i saying" || lower == "what did i say" {
            return .recallSpoken
        }
        if lower == "what did i see" || lower == "what was i looking at" {
            return .recallSeen
        }
        if lower == "do that" || lower == "yes do it" || lower == "go ahead" || lower == "handle that" {
            let bot = AssistantRoster.defaultBot(in: bots).name
            return .handoff(bot: bot, ask: nil)
        }
        let roster = AssistantRoster.normalized(bots).sorted { $0.name.count > $1.name.count }
        for bot in roster {
            let name = bot.name.lowercased()
            let handles = ["have \(name) handle ", "ask \(name) to handle "]
            for prefix in handles where lower.hasPrefix(prefix) {
                let rest = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                let ask = rest.isEmpty || ["it", "that", "this"].contains(rest) ? nil : "Handle \(rest)."
                return .handoff(bot: bot.name, ask: ask)
            }
            if lower == "send that to \(name)" || lower == "send this to \(name)" {
                return .handoff(bot: bot.name, ask: nil)
            }
        }
        return nil
    }

    private static func dictation(_ lower: String, original: String, target: String) -> JarvisRoute? {
        let notes = ["take a note", "make a note", "note to self", "take note"]
        let drafts = ["draft a reply", "draft an email", "write a reply", "draft a message"]
        if let kind = match(lower, notes) {
            let body = String(original.dropFirst(kind.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { return .dictate(kind: "note") }
            return .relay(RelayTurn(intent: "note", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
        }
        if let kind = match(lower, drafts) {
            let body = String(original.dropFirst(kind.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { return .dictate(kind: "draft") }
            return .relay(RelayTurn(intent: "draft", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
        }
        return nil
    }

    private static func isTask(_ lower: String) -> Bool {
        let keys = ["order", "orders", "store", "email", "schedule", "calendar", "remind", "reminder",
                    "tell my assistant", "buy ", "tiktok", "amazon", "slack", "book ", "reservation",
                    "inbox", "text ", "message ", "do this", "phoenix do"]
        return keys.contains { lower.contains($0) }
    }

    private static func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func match(_ text: String, _ phrases: [String]) -> String? {
        phrases.first { text.hasPrefix($0) }
    }
}
