// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - FastModeRouter.swift
// Rules first. `classifier` is the hook for a later model. Nil means the rules decide.
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
}

protocol JarvisRouteClassifying: AnyObject {
    func classify(_ text: String) async -> JarvisRoute?
}

enum FastModeRouter {
    /// Swap in an LLM classifier without touching call sites. A nil result falls through to the rules.
    nonisolated(unsafe) static weak var classifier: JarvisRouteClassifying?

    struct Context {
        var fastMode: Bool
        var isPro: Bool
        var bots: [AssistantBot]
        var instantReady: Bool
        var clipEnabled: Bool
    }

    static func decide(_ text: String, context: Context) async -> JarvisRoute {
        if let classified = await classifier?.classify(text) { return classified }
        return rules(text, context: context)
    }

    static func rules(_ text: String, context: Context) -> JarvisRoute {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = AssistantRoster.defaultBot(in: context.bots).name

        if contains(lower, ["status report", "all hands", "everyone check in", "everyone report"]) {
            guard context.isPro else { return .needsPro("All hands is a Pro feature.") }
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
            if context.fastMode && context.instantReady {
                return .instant(text: text, photo: true, cacheable: false)
            }
            return .relay(RelayTurn(intent: "look", targetBot: fallback, text: text, photo: true, clip: false, cacheable: false))
        }

        let addressed = AssistantRoster.address(in: text, bots: context.bots)
        if addressed.explicit && !addressed.bot.isDefault && !context.isPro {
            return .needsPro("More than one assistant is a Pro feature.")
        }
        let target = addressed.bot.name
        let body = addressed.remainder

        if isTask(body.lowercased()) || (addressed.explicit && !addressed.bot.isDefault) {
            return .relay(RelayTurn(intent: "message", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
        }
        if context.fastMode && context.instantReady {
            return .instant(text: body, photo: false, cacheable: true)
        }
        return .relay(RelayTurn(intent: "message", targetBot: target, text: body, photo: false, clip: false, cacheable: false))
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
                    "inbox", "text ", "message ", "do this", "jarvis do"]
        return keys.contains { lower.contains($0) }
    }

    private static func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func match(_ text: String, _ phrases: [String]) -> String? {
        phrases.first { text.hasPrefix($0) }
    }
}
