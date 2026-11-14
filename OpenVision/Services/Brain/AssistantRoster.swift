// Jarvis - AssistantRoster.swift
// The wearer's assistants. The shipped app starts with one assistant named by them.
// Fire Fox, Indy, Driver, and Rally are not compiled in. The owner types those in Settings.

import Foundation

struct AssistantBot: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var voiceIdentifier: String?
    var isDefault: Bool

    static let allBots = "all"
}

enum AssistantRoster {
    /// The owner's assistants. Names are not secrets. The relay URL and token are.
    static let seed: [AssistantBot] = [
        AssistantBot(id: "fire-fox", name: "Fire Fox", voiceIdentifier: nil, isDefault: true),
        AssistantBot(id: "indy", name: "Indy", voiceIdentifier: nil, isDefault: false),
        AssistantBot(id: "driver", name: "Driver", voiceIdentifier: nil, isDefault: false),
        AssistantBot(id: "rally", name: "Rally", voiceIdentifier: nil, isDefault: false),
    ]

    static func normalized(_ bots: [AssistantBot]) -> [AssistantBot] {
        var cleaned = bots
            .map { bot -> AssistantBot in
                var copy = bot
                copy.name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return copy
            }
            .filter { !$0.name.isEmpty && $0.name.lowercased() != AssistantBot.allBots }
        if cleaned.isEmpty { cleaned = seed }
        if !cleaned.contains(where: \.isDefault) {
            cleaned[0].isDefault = true
        }
        var seenDefault = false
        for index in cleaned.indices {
            if cleaned[index].isDefault {
                if seenDefault { cleaned[index].isDefault = false }
                seenDefault = true
            }
        }
        return cleaned
    }

    static func defaultBot(in bots: [AssistantBot]) -> AssistantBot {
        normalized(bots).first(where: \.isDefault) ?? seed[0]
    }

    /// "ask Indy to …", "tell Driver …", "hey Rally". Longest name wins.
    static func address(in text: String, bots: [AssistantBot]) -> (bot: AssistantBot, remainder: String, explicit: Bool) {
        let roster = normalized(bots).sorted { $0.name.count > $1.name.count }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for bot in roster {
            let name = bot.name.lowercased()
            let prefixes = [
                "ask \(name) to ", "ask \(name) ",
                "tell \(name) to ", "tell \(name) that ", "tell \(name) ",
                "hey \(name), ", "hey \(name) ", "hey \(name)",
            ]
            for prefix in prefixes where lower.hasPrefix(prefix) {
                let rest = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (bot, rest.isEmpty ? "checking in" : rest, true)
            }
        }
        return (defaultBot(in: roster), trimmed, false)
    }

    struct SpokenLine {
        var text: String
        var voiceIdentifier: String?
    }

    static func spoken(text: String, fromBot: String?, bots: [AssistantBot], alwaysName: Bool) -> SpokenLine {
        let roster = normalized(bots)
        let fallback = defaultBot(in: roster)
        let name = (fromBot?.isEmpty == false ? fromBot! : fallback.name)
        let match = roster.first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
        let voice = match?.voiceIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        let isDefault = match?.isDefault == true || name.compare(fallback.name, options: .caseInsensitive) == .orderedSame
        if alwaysName || !isDefault {
            return SpokenLine(text: "\(match?.name ?? name) says: \(text)", voiceIdentifier: voice)
        }
        return SpokenLine(text: text, voiceIdentifier: voice)
    }
}
