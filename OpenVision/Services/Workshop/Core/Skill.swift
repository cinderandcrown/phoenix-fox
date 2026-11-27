// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Skills: spoken commands added by a file, with no code in them.
//
// A skill says which phrases start it, what the glasses capture (a photo, the text in
// view, the place, the time), and what to ask one of the wearer's assistants. That is all
// it can say. It cannot run anything on the phone and it cannot name a server: the only
// place a skill can send what it captures is the wearer's own relay. That makes a skill
// safe to take from a stranger in a way a plugin with code is not, and the wearer is
// shown exactly what it captures before it is added.
//
// The format is documented in docs/SKILLS.md.

import Foundation

struct Skill: Codable, Equatable, Identifiable, Sendable {
    enum Capture: String, Codable, CaseIterable, Sendable {
        /// A picture through the glasses, sent to the assistant.
        case photo
        /// The words in view, read on the phone. The picture is not sent.
        case text
        /// Where the wearer is, to about ten meters.
        case place
        /// The date and time on the phone.
        case time
    }

    enum Speak: String, Codable, Sendable {
        /// The assistant's answer is spoken.
        case reply
        /// Nothing is spoken but "Sent". The answer goes in the task log.
        case quiet
    }

    /// The version of the format this file is written in.
    var format: Int
    var id: String
    var name: String
    var about: String?
    var phrases: [String]
    var capture: [Capture]
    /// The assistant to ask, by name. Left out, the wearer's default assistant is asked.
    var bot: String?
    var ask: String
    var speak: Speak

    static let currentFormat = 1
    static let limit = 30

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case format, id, name, about, phrases, capture, bot, ask, speak
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(format: Int = Skill.currentFormat, id: String, name: String, about: String? = nil, phrases: [String],
         capture: [Capture] = [], bot: String? = nil, ask: String, speak: Speak = .reply) {
        self.format = format
        self.id = id
        self.name = name
        self.about = about
        self.phrases = phrases
        self.capture = capture
        self.bot = bot
        self.ask = ask
        self.speak = speak
    }

    init(from decoder: Decoder) throws {
        // A key this version does not know is refused, not ignored: a file that asks for
        // something the app cannot do must not look as if it was accepted.
        let known = Set(CodingKeys.allCases.map(\.stringValue))
        let all = try decoder.container(keyedBy: AnyKey.self)
        if let stray = all.allKeys.map(\.stringValue).sorted().first(where: { !known.contains($0) }) {
            throw SkillError.unknownField(stray)
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decodeIfPresent(Int.self, forKey: .format) ?? Skill.currentFormat
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        about = try values.decodeIfPresent(String.self, forKey: .about)
        phrases = try values.decode([String].self, forKey: .phrases)
        let captures = try values.decodeIfPresent([String].self, forKey: .capture) ?? []
        capture = try captures.map { raw in
            guard let value = Capture(rawValue: raw) else { throw SkillError.unknownCapture(raw) }
            return value
        }
        bot = try values.decodeIfPresent(String.self, forKey: .bot)
        ask = try values.decode(String.self, forKey: .ask)
        let spoken = try values.decodeIfPresent(String.self, forKey: .speak) ?? Speak.reply.rawValue
        guard let speak = Speak(rawValue: spoken) else { throw SkillError.unknownSpeak(spoken) }
        self.speak = speak
    }
}

enum SkillError: Error, Equatable, Sendable {
    case notJSON
    case missingField
    case unknownField(String)
    case unknownCapture(String)
    case unknownSpeak(String)
    case newerFormat(Int)
    case badID
    case badName
    case noPhrases
    case tooManyPhrases
    case phraseTooShort(String)
    case phraseReserved(String)
    case phraseSlot(String)
    case phraseTaken(String, by: String)
    case askEmpty
    case askTooLong
    case unknownPlaceholder(String)
    case slotNotInEveryPhrase(String)
    case address(String)
    case tooManySkills

    /// The reason, in words the person adding the skill can act on.
    var message: String {
        switch self {
        case .notJSON: return "This is not a skill file. A skill is a JSON object."
        case .missingField: return "The skill needs an id, a name, at least one phrase, and an ask."
        case .unknownField(let field): return "The skill has a field this version does not know: \"\(field)\"."
        case .unknownCapture(let value): return "The skill asks to capture \"\(value)\". It can capture photo, text, place, and time."
        case .unknownSpeak(let value): return "\"speak\" is \"\(value)\". It can be \"reply\" or \"quiet\"."
        case .newerFormat(let format): return "The skill is written in format \(format). This version reads format \(Skill.currentFormat)."
        case .badID: return "The id must be 3 to 40 lowercase letters, digits, and hyphens."
        case .badName: return "The name must be 1 to 40 characters."
        case .noPhrases: return "The skill needs at least one phrase."
        case .tooManyPhrases: return "A skill can have at most 8 phrases."
        case .phraseTooShort(let phrase): return "The phrase \"\(phrase)\" is too short. A phrase needs at least two words before any slot."
        case .phraseReserved(let phrase): return "The phrase \"\(phrase)\" starts with a word that is kept for the app, such as \"stop\" or \"call\"."
        case .phraseSlot(let phrase): return "In \"\(phrase)\", a slot in braces can only be the last thing in the phrase, and there can be one."
        case .phraseTaken(let phrase, let other): return "The phrase \"\(phrase)\" is already used by the skill \"\(other)\"."
        case .askEmpty: return "The ask is empty."
        case .askTooLong: return "The ask is longer than 1,000 characters."
        case .unknownPlaceholder(let name): return "The ask uses {\(name)}, which is not a slot in the phrases and is not captured."
        case .slotNotInEveryPhrase(let name): return "The ask uses {\(name)}, so every phrase must end with {\(name)}."
        case .address(let field): return "The \(field) contains a web address. A skill cannot name anywhere to send things."
        case .tooManySkills: return "There are already \(Skill.limit) skills. Remove one first."
        }
    }
}

extension Skill {
    /// Words a phrase cannot start with: they belong to commands that must always work.
    static let reservedLeads: Set<String> = [
        "stop", "cancel", "quiet", "call", "text", "message", "emergency", "help", "yes", "no", "phoenix", "hey", "undo",
    ]

    /// A phrase as it is matched, and the name of the slot it ends with, if it has one.
    struct Phrase: Equatable, Sendable {
        var words: String
        var slot: String?

        /// The phrase as it is written in a skill file.
        var written: String {
            slot.map { "\(words) {\($0)}" } ?? words
        }
    }

    /// Reads and checks a skill file.
    static func decode(_ json: String) throws -> Skill {
        guard let data = json.data(using: .utf8), !data.isEmpty else { throw SkillError.notJSON }
        let skill: Skill
        do {
            skill = try JSONDecoder().decode(Skill.self, from: data)
        } catch let error as SkillError {
            throw error
        } catch DecodingError.keyNotFound, DecodingError.valueNotFound, DecodingError.typeMismatch {
            throw SkillError.missingField
        } catch {
            throw SkillError.notJSON
        }
        return try skill.validated()
    }

    /// The file for this skill, for sharing or editing.
    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    /// The skill with its fields trimmed, or the first thing wrong with it.
    func validated() throws -> Skill {
        var skill = self
        guard skill.format <= Skill.currentFormat else { throw SkillError.newerFormat(skill.format) }
        skill.format = Skill.currentFormat

        let idCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard (3...40).contains(skill.id.count), skill.id.allSatisfy(idCharacters.contains),
              skill.id.first != "-", skill.id.last != "-" else { throw SkillError.badID }

        skill.name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...40).contains(skill.name.count) else { throw SkillError.badName }
        skill.about = skill.about?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let about = skill.about, about.count > 200 { skill.about = String(about.prefix(200)) }
        skill.bot = skill.bot?.trimmingCharacters(in: .whitespacesAndNewlines)
        if skill.bot?.isEmpty == true { skill.bot = nil }

        guard !skill.phrases.isEmpty else { throw SkillError.noPhrases }
        guard skill.phrases.count <= 8 else { throw SkillError.tooManyPhrases }
        let parsed = try skill.phrases.map(Skill.phrase)
        skill.phrases = parsed.map(\.written)

        skill.ask = skill.ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !skill.ask.isEmpty else { throw SkillError.askEmpty }
        guard skill.ask.count <= 1_000 else { throw SkillError.askTooLong }

        for (field, value) in [("name", skill.name), ("about", skill.about ?? ""), ("ask", skill.ask), ("bot", skill.bot ?? "")]
            + skill.phrases.map({ ("phrases", $0) }) where Skill.hasAddress(value) {
            throw SkillError.address(field)
        }

        var captured = Set(skill.capture)
        skill.capture = Capture.allCases.filter { captured.remove($0) != nil }
        let builtIn: [String: Capture] = ["text": .text, "place": .place, "time": .time]
        let slots = Set(parsed.compactMap(\.slot))
        for name in Skill.placeholders(in: skill.ask) {
            if let capture = builtIn[name], !slots.contains(name) {
                guard skill.capture.contains(capture) else { throw SkillError.unknownPlaceholder(name) }
                continue
            }
            guard slots.contains(name) else { throw SkillError.unknownPlaceholder(name) }
            guard parsed.allSatisfy({ $0.slot == name }) else { throw SkillError.slotNotInEveryPhrase(name) }
        }
        return skill
    }

    /// Checks a phrase and puts it in the form it is matched in.
    static func phrase(_ raw: String) throws -> Phrase {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var body = trimmed
        var slot: String?
        if let open = trimmed.firstIndex(of: "{") {
            guard trimmed.hasSuffix("}"), trimmed.filter({ $0 == "{" }).count == 1, trimmed.filter({ $0 == "}" }).count == 1 else {
                throw SkillError.phraseSlot(raw)
            }
            let name = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
            guard !name.isEmpty, name.allSatisfy({ $0.isLetter && $0.isASCII }) else { throw SkillError.phraseSlot(raw) }
            slot = name.lowercased()
            body = String(trimmed[..<open])
        } else if trimmed.contains("}") {
            throw SkillError.phraseSlot(raw)
        }
        let words = WorkshopText.words(body)
        guard words.count >= 2, words.joined().count >= 6 else { throw SkillError.phraseTooShort(raw) }
        guard let first = words.first, !reservedLeads.contains(first) else { throw SkillError.phraseReserved(raw) }
        return Phrase(words: words.joined(separator: " "), slot: slot)
    }

    private static func placeholders(in ask: String) -> [String] {
        var names: [String] = []
        var rest = Substring(ask)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            names.append(rest[rest.index(after: open)..<close].lowercased())
            rest = rest[rest.index(after: close)...]
        }
        return names
    }

    private static func hasAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        if ["http:", "https:", "www.", "ftp:", "://", "mailto:"].contains(where: lower.contains) { return true }
        // "example.com/path" and "10.0.0.1".
        return lower.range(of: #"[a-z0-9-]+\.(com|net|org|io|dev|app|ai|co|me|xyz|info|ru|cn)\b|\b\d{1,3}(\.\d{1,3}){3}\b"#, options: .regularExpression) != nil
    }

    // MARK: - Using a skill

    /// What the wearer is shown before a skill is added, and afterwards in its row.
    var permissions: [String] {
        let who = bot ?? "your assistant"
        var lines: [String] = []
        let phrases = (try? self.phrases.map(Skill.phrase)) ?? []
        if phrases.contains(where: { $0.slot != nil }) {
            lines.append("Sends what you say after the phrase to \(who).")
        }
        for item in capture {
            switch item {
            case .photo: lines.append("Takes a photo through the glasses and sends it to \(who). The capture light comes on.")
            case .text: lines.append("Reads the words in view on the phone and sends the words to \(who). The capture light comes on. The picture is not sent.")
            case .place: lines.append("Sends where you are to \(who).")
            case .time: lines.append("Sends the date and time to \(who).")
            }
        }
        if lines.isEmpty { lines.append("Sends a fixed request to \(who). Nothing is captured.") }
        lines.append(speak == .reply ? "Speaks the answer." : "Says only \"Sent\". The answer goes in the task log.")
        return lines
    }

    /// The request sent to the assistant, with every placeholder filled.
    func request(slot: String?, text: String?, place: String?, time: String?) -> String {
        let slots = Set(((try? phrases.map(Skill.phrase)) ?? []).compactMap(\.slot))
        var result = ""
        var rest = Substring(ask)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let name = rest[rest.index(after: open)..<close].lowercased()
            if slots.contains(name) {
                result += slot ?? ""
            } else {
                switch name {
                case "text": result += text.flatMap { $0.isEmpty ? nil : $0 } ?? "(no words could be read)"
                case "place": result += place ?? "(the place is not known)"
                case "time": result += time ?? ""
                default: break
                }
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }
}

enum Skills {
    struct Match: Equatable, Sendable {
        var skill: Skill
        /// What was said after the phrase, when the phrase ends with a slot.
        var slot: String?
    }

    /// The skill a sentence starts, if any. The longest phrase wins.
    static func match(_ utterance: String, in skills: [Skill]) -> Match? {
        let said = WorkshopText.command(utterance)
        guard !said.isEmpty else { return nil }
        var best: (match: Match, length: Int)?
        for skill in skills {
            for raw in skill.phrases {
                guard let phrase = try? Skill.phrase(raw) else { continue }
                let slot: String?
                if phrase.slot == nil {
                    guard said == phrase.words else { continue }
                    slot = nil
                } else {
                    guard said.hasPrefix(phrase.words + " ") else { continue }
                    slot = slotText(utterance, after: phrase.words)
                }
                if best == nil || phrase.words.count > (best?.length ?? 0) {
                    best = (Match(skill: skill, slot: slot), phrase.words.count)
                }
            }
        }
        return best?.match
    }

    /// What was said after the phrase, as it was said: capitals and numbers kept.
    private static func slotText(_ utterance: String, after phrase: String) -> String {
        let count = phrase.split(separator: " ").count
        let original = utterance.split(whereSeparator: \.isWhitespace).map(String.init)
        // Find where the phrase ends in the original words, which may start with the wake word.
        let plain = original.map { WorkshopText.words($0).joined() }
        let target = phrase.split(separator: " ").map(String.init)
        if count <= plain.count {
            for start in 0...(plain.count - count) where Array(plain[start..<(start + count)]) == target {
                let rest = original[(start + count)...].joined(separator: " ")
                return rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?"))
            }
        }
        return String(WorkshopText.command(utterance).dropFirst(phrase.count + 1))
    }

    /// Adds or replaces a skill. Throws when it is invalid, when the list is full, or when
    /// one of its phrases already belongs to another skill.
    static func install(_ candidate: Skill, into skills: inout [Skill]) throws {
        let skill = try candidate.validated()
        let others = skills.filter { $0.id != skill.id }
        guard others.count < Skill.limit else { throw SkillError.tooManySkills }
        let mine = try skill.phrases.map(Skill.phrase)
        for other in others {
            for raw in other.phrases {
                guard let theirs = try? Skill.phrase(raw) else { continue }
                if let clash = mine.first(where: { $0.words == theirs.words }) {
                    throw SkillError.phraseTaken(clash.words, by: other.name)
                }
            }
        }
        if let index = skills.firstIndex(where: { $0.id == skill.id }) {
            skills[index] = skill
        } else {
            skills.append(skill)
        }
    }

    /// Skills that ship with the app as examples. None is installed until the owner adds it.
    static let examples: [Skill] = [
        Skill(
            id: "price-check",
            name: "Price check",
            about: "Look at a product or a price tag and hear whether the price is a good one.",
            phrases: ["price check", "is this a good price"],
            capture: [.photo],
            bot: "Indy",
            ask: "Find the product in the photo. In two sentences, say what it usually sells for and whether the price shown is a good one."
        ),
        Skill(
            id: "expense",
            name: "Log an expense",
            about: "Say what you spent. The time and place go with it.",
            phrases: ["log an expense {what}", "expense this {what}"],
            capture: [.place, .time],
            bot: "Rally",
            ask: "Record this expense: {what}. Time: {time}. Place: {place}. Reply with the one line you recorded.",
            speak: .reply
        ),
        Skill(
            id: "plant-doctor",
            name: "Plant doctor",
            about: "Look at a plant that is not doing well.",
            phrases: ["what's wrong with this plant", "plant doctor"],
            capture: [.photo],
            ask: "This is a photo of a plant. In three sentences at most, say what looks wrong with it and the first thing to do."
        ),
        Skill(
            id: "standup-note",
            name: "Standup note",
            about: "Add a line to tomorrow's standup without stopping what you are doing.",
            phrases: ["standup note {note}"],
            bot: "Fire Fox",
            ask: "Add this to my standup notes for tomorrow: {note}",
            speak: .quiet
        ),
        Skill(
            id: "sign-explainer",
            name: "Explain this notice",
            about: "Reads a notice or a form on the phone and has it explained in plain words.",
            phrases: ["explain this notice", "what does this notice mean"],
            capture: [.text],
            ask: "This is the text of a notice I am looking at. Explain in plain words what it asks me to do, in three sentences at most.\n\n{text}"
        ),
    ]
}
