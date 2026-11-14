// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Mind meld: an on-phone log of what the wearer said, and the words of a look
// he asked for. It does not store camera bytes. A photo is kept only by the
// explicit "remember" path, and only while the glasses capture light is on.
// The log stays off until he says "mind meld on".

import Foundation

struct MindEpisode: Codable, Equatable, Sendable {
    var at: Date
    var said: String
    var heard: String?
    var bot: String?
    /// The question he asked while the camera was on. Not an image.
    var saw: String?
}

struct MindSuggestion: Equatable, Sendable {
    var bot: String
    var ask: String
    var spoken: String
}

enum MindCommand: Equatable {
    case consent(Bool)
    case anticipate
    case recallSpoken
    case recallSeen
    case handoff(bot: String, ask: String?)
}

enum MindMeldPlanner {
    static func anticipate(
        episodes: [MindEpisode],
        now: Date,
        bots: [String],
        logging: Bool,
        calendar: Calendar = .current
    ) -> MindSuggestion {
        let roster = bots.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let bot = preferredBot(episodes: episodes, roster: roster.isEmpty ? ["Fire Fox"] : roster)
        let hour = calendar.component(.hour, from: now)
        let last = episodes.max(by: { $0.at < $1.at })

        if let last, logging {
            let follow = last.said.trimmingCharacters(in: .whitespacesAndNewlines)
            let ask = follow.isEmpty ? "What should I take care of next?" : "Follow up on this: \(follow)"
            return MindSuggestion(
                bot: bot,
                ask: ask,
                spoken: "I'd ask \(bot) to follow up on \(clip(follow, 80)). Say do that, or name another assistant."
            )
        }

        if (5..<11).contains(hour) {
            return MindSuggestion(
                bot: bot,
                ask: "Give me a short morning brief of what needs me today.",
                spoken: logging
                    ? "Nothing is in the log yet. I can ask \(bot) for a morning brief. Say do that."
                    : "Mind meld is off, so I am not keeping what you say. I can still ask \(bot) for a morning brief. Say do that, or say mind meld on."
            )
        }

        return MindSuggestion(
            bot: bot,
            ask: "What should I take care of next?",
            spoken: logging
                ? "The log is empty. Say what you want \(bot) to do, or say do that and I'll ask what's next."
                : "Mind meld is off. Say mind meld on if you want me to keep what you say on this phone. I can still ask \(bot) what's next. Say do that."
        )
    }

    static func recallSpoken(_ episodes: [MindEpisode], logging: Bool) -> String {
        guard logging else {
            return "Mind meld is off. I am not keeping a running log. Say mind meld on. Notes you told me to remember are separate, and still on this phone."
        }
        guard let last = episodes.max(by: { $0.at < $1.at }) else {
            return "The log is empty. Talk after mind meld is on and I will keep the words here."
        }
        if let heard = last.heard, !heard.isEmpty {
            let who = last.bot.map { " \($0) said" } ?? ""
            return "You said \(clip(last.said, 120)).\(who) \(clip(heard, 120))"
        }
        return "You said \(clip(last.said, 160))."
    }

    static func recallSeen(_ episodes: [MindEpisode], logging: Bool) -> String {
        guard logging else {
            return "Mind meld is off. I never keep a camera roll. Say look at this, or remember this, while the capture light is on."
        }
        let seen = episodes.filter { ($0.saw?.isEmpty == false) }.max(by: { $0.at < $1.at })
        guard let seen, let saw = seen.saw else {
            return "I don't have a look in the log. I only keep the words of a look you asked for. The capture light is on for that shot, and I do not store the photo unless you say remember."
        }
        return "The last thing you asked me to look at was \(clip(saw, 160))."
    }

    static func handoffAsk(pending: MindSuggestion?, episodes: [MindEpisode], explicit: String?) -> String? {
        if let explicit {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !placeholders.contains(trimmed.lowercased()) {
                return trimmed
            }
        }
        if let pending, !pending.ask.isEmpty { return pending.ask }
        return episodes.max(by: { $0.at < $1.at })?.said
    }

    private static let placeholders: Set<String> = ["it", "that", "this", "them"]

    private static func preferredBot(episodes: [MindEpisode], roster: [String]) -> String {
        let names = roster
        if let mentioned = episodes.reversed().compactMap({ episode -> String? in
            let hay = (episode.said + " " + (episode.bot ?? "")).lowercased()
            return names.first { hay.contains($0.lowercased()) }
        }).first {
            return mentioned
        }
        return names[0]
    }

    private static func clip(_ text: String, _ max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }
}

@MainActor
enum MindMeld {
    private static let pendingKey = "phoenixfox.mindmeld.pending"
    private static let limit = 40

    static func note(said: String, heard: String?, bot: String?, saw: String?) {
        let trimmed = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var rows = load()
        rows.append(MindEpisode(at: Date(), said: trimmed, heard: heard, bot: bot, saw: saw))
        if rows.count > limit { rows.removeFirst(rows.count - limit) }
        save(rows)
    }

    static func episodes() -> [MindEpisode] { load() }

    static func anticipate(bots: [String]) -> MindSuggestion {
        let logging = SettingsManager.shared.settings.mindMeldEnabled
        return MindMeldPlanner.anticipate(episodes: load(), now: Date(), bots: bots, logging: logging)
    }

    static func recallSpoken() -> String {
        MindMeldPlanner.recallSpoken(load(), logging: SettingsManager.shared.settings.mindMeldEnabled)
    }

    static func recallSeen() -> String {
        MindMeldPlanner.recallSeen(load(), logging: SettingsManager.shared.settings.mindMeldEnabled)
    }

    static func storePending(_ suggestion: MindSuggestion) {
        let payload: [String: String] = [
            "bot": suggestion.bot,
            "ask": suggestion.ask,
            "spoken": suggestion.spoken,
        ]
        UserDefaults.standard.set(payload, forKey: pendingKey)
    }

    static func pending() -> MindSuggestion? {
        guard let payload = UserDefaults.standard.dictionary(forKey: pendingKey) as? [String: String],
              let bot = payload["bot"], let ask = payload["ask"], let spoken = payload["spoken"] else { return nil }
        return MindSuggestion(bot: bot, ask: ask, spoken: spoken)
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }

    private static func fileURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("phoenix-mindmeld.json")
    }

    private static func load() -> [MindEpisode] {
        guard let data = try? Data(contentsOf: fileURL()) else { return [] }
        return (try? JSONDecoder().decode([MindEpisode].self, from: data)) ?? []
    }

    private static func save(_ rows: [MindEpisode]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: fileURL(), options: .atomic)
    }
}
