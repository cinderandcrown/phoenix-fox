// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The spoken commands of the accessibility suite.
//
// Every accessibility feature can be reached by voice alone, so this is the suite's whole
// control surface. Matching is by fixed phrases, on the phone, with no model in the loop:
// "read this" must work in a basement with no signal, and must never be routed to a bot
// by mistake. A sentence that matches nothing here returns nil and goes on to the
// assistant as before.

import Foundation

enum AccessCommand: Equatable, Sendable {
    // Seeing
    case read(ReadScope)
    case readMore, readBack, readAgain, stopReading
    case readLabel
    case identifyMoney
    case identifyColor
    case describeScene
    case find(String)
    case whoIsThis
    case rememberFace(name: String)
    case forgetFace(name: String)
    case forgetAllFaces
    case faceRecognition(Bool)

    // Getting around
    case guide(Bool)
    case walk(to: String)
    case stopWalking
    case nextTurn
    case whereAmI
    case emergencyCall
    case setEmergencyContact(String)

    // Hearing
    case captions(Bool)
    case soundAlerts(Bool)
    case whatWasSaid
    case saveTranscript
    case clearTranscript

    // Speech and movement
    case pace(SpeechPace)
    case extraTime(Bool)
    case help

    // Memory and tasks
    case startTask(String)
    case teachRoutine(name: String, steps: [String])
    case listRoutines
    case deleteRoutine(String)
    case taskNext, taskBack, taskRepeat, taskWhere, taskStop
    case whatWasIDoing
    case recall(Bool)
    case forgetActivity
    case remindWhenSeeing(person: String, note: String)

    enum ReadScope: Equatable, Sendable { case everything, sign }

    /// What a bare "next" or "repeat" refers to right now.
    enum Focus: Equatable, Sendable { case none, reading, task }

    struct Context: Equatable, Sendable {
        var focus: Focus = .none
        /// Guide mode is on, so "find the …" is about what the camera sees.
        var guiding = false
        var walking = false

        init(focus: Focus = .none, guiding: Bool = false, walking: Bool = false) {
            self.focus = focus
            self.guiding = guiding
            self.walking = walking
        }
    }

    static func parse(_ utterance: String, context: Context = Context()) -> AccessCommand? {
        let loose = utterance.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var text = String(loose.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == " " ? $0 : " " })
            .split(separator: " ").joined(separator: " ")
        for lead in ["hey phoenix ", "ok phoenix ", "okay phoenix ", "phoenix ", "please ", "can you ", "could you ", "would you ", "i want you to ", "i need you to "] {
            if text.hasPrefix(lead) { text = String(text.dropFirst(lead.count)) }
        }
        if text.hasSuffix(" please") { text = String(text.dropLast(7)) }
        guard !text.isEmpty else { return nil }

        return focused(text, context)
            ?? seeing(text, context)
            ?? faces(text)
            ?? gettingAround(text, context)
            ?? hearing(text)
            ?? speech(text)
            ?? tasks(text, loose)
            ?? memory(text)
    }

    // MARK: - Short words that depend on what is happening

    private static func focused(_ text: String, _ context: Context) -> AccessCommand? {
        switch context.focus {
        case .reading:
            if ["more", "next", "continue", "go on", "keep going"].contains(text) { return .readMore }
            if ["back", "go back", "previous"].contains(text) { return .readBack }
            if ["again", "repeat", "repeat that", "say that again"].contains(text) { return .readAgain }
            if ["stop", "that's enough", "enough"].contains(text) { return .stopReading }
        case .task:
            if ["next", "next step", "done", "i'm done", "finished", "okay next", "ok next", "continue", "got it", "what's next"].contains(text) { return .taskNext }
            if ["back", "go back", "previous", "previous step", "last step"].contains(text) { return .taskBack }
            if ["again", "repeat", "repeat that", "say that again", "what was that", "repeat the step"].contains(text) { return .taskRepeat }
            if ["what step am i on", "which step", "how many steps are left"].contains(text) { return .taskWhere }
            // A bare "stop" is left alone: it silences speech, and must not end the task.
            if ["quit", "stop the task", "stop task", "cancel the task", "end the task", "i'm stopping"].contains(text) { return .taskStop }
        case .none:
            break
        }
        if ["read more", "keep reading", "continue reading"].contains(text) { return .readMore }
        if ["read that again", "read it again"].contains(text) { return .readAgain }
        if ["stop reading"].contains(text) { return .stopReading }
        if ["next step"].contains(text) { return .taskNext }
        if ["previous step"].contains(text) { return .taskBack }
        if ["repeat the step", "what step am i on"].contains(text) { return text == "repeat the step" ? .taskRepeat : .taskWhere }
        if ["stop the task", "cancel the task", "end the task"].contains(text) { return .taskStop }
        return nil
    }

    // MARK: - Seeing

    private static func seeing(_ text: String, _ context: Context) -> AccessCommand? {
        if has(text, ["read the sign", "read that sign", "read this sign", "what does the sign say", "what does that sign say", "what's that sign", "what does this sign say"]) {
            return .read(.sign)
        }
        if has(text, ["read the label", "read this label", "read the bottle", "read the prescription", "read the box"])
            || (has(text, ["medication", "medicine", "pill", "prescription"]) && has(text, ["what", "which", "read", "what's"])
                && has(text, ["this", "that", "these", "holding", "is it"])) {
            return .readLabel
        }
        if has(text, ["bill", "banknote", "money", "cash", "currency"]) && has(text, ["what", "how much", "which", "identify"])
            && has(text, ["this", "that", "holding", "is it"]) {
            return .identifyMoney
        }
        if has(text, ["what color", "what colour", "which color", "which colour", "identify the color", "identify this color", "tell me the color"]) {
            return .identifyColor
        }
        let readable = ["this", "that", "it", "this to me", "that to me", "it to me", "aloud", "out loud", "to me"]
        let things = ["page", "document", "letter", "menu", "text", "mail", "paper", "screen", "book", "receipt", "card", "note", "envelope", "poster"]
        if text.hasPrefix("read ") {
            let rest = String(text.dropFirst(5))
            if readable.contains(rest) || things.contains(where: { rest.hasSuffix($0) || rest.hasSuffix($0 + " to me") }) {
                return .read(.everything)
            }
        }
        if ["what does this say", "what does it say", "what does that say", "what's written here", "what is written here"].contains(text) {
            return .read(.everything)
        }
        if has(text, ["describe the scene", "describe my surroundings", "describe the room", "describe what's in front of me", "what's in front of me", "what is in front of me", "what's around me", "what is around me"]) {
            return .describeScene
        }
        if let target = after(text, ["where is the ", "where's the ", "where is a ", "where's a ", "find the ", "find a ", "find an ", "find me a ", "find me the ", "help me find the ", "help me find a ", "is there a ", "is there an "]) {
            let thing = strip(target, suffixes: [" nearby", " here", " around here", " around", " in front of me", " near me"])
            let known = ["door", "exit", "entrance", "stairs", "staircase", "steps", "elevator", "escalator", "restroom", "bathroom", "toilet", "chair", "seat", "bench", "table", "counter", "trash can", "bin", "crosswalk", "sign", "handle", "person", "people", "car", "bus"]
            if thing.split(separator: " ").count <= 3, context.guiding || known.contains(thing) {
                return .find(thing)
            }
        }
        return nil
    }

    private static func faces(_ text: String) -> AccessCommand? {
        if ["who is this", "who's this", "who is that", "who's that", "who is in front of me", "who's in front of me", "who am i looking at", "who's here", "who is here"].contains(text)
            || has(text, ["do you recognize this person", "do you recognize them", "do you recognize him", "do you recognize her"]) {
            return .whoIsThis
        }
        if let name = after(text, ["remember this person as ", "remember this face as ", "save this face as ", "save this person as ", "remember them as ", "remember him as ", "remember her as "]) {
            return name.isEmpty ? nil : .rememberFace(name: title(name))
        }
        if ["forget all faces", "delete all faces", "forget everyone's face", "forget every face"].contains(text) { return .forgetAllFaces }
        if text.hasSuffix("'s face"), let name = after(text, ["forget ", "delete ", "remove "]) {
            return .forgetFace(name: title(String(name.dropLast(7))))
        }
        if let name = after(text, ["forget the face of ", "delete the face of "]) { return .forgetFace(name: title(name)) }
        if let on = toggle(text, ["face recognition"]) { return .faceRecognition(on) }
        return nil
    }

    // MARK: - Getting around

    private static func gettingAround(_ text: String, _ context: Context) -> AccessCommand? {
        if let on = toggle(text, ["guide mode", "guiding"]) { return .guide(on) }
        if ["guide me", "start guiding me", "be my guide"].contains(text) { return .guide(true) }
        if ["stop guiding me"].contains(text) { return .guide(false) }
        if let place = after(text, ["walk me to ", "guide me to ", "walking directions to ", "give me walking directions to "]) {
            return place.isEmpty ? nil : .walk(to: place)
        }
        if ["stop directions", "stop the directions", "stop walking directions", "stop navigation", "stop navigating", "end the route", "cancel the route", "cancel directions"].contains(text) {
            return .stopWalking
        }
        if ["next turn", "what's my next turn", "what is my next turn", "what's the next turn", "how far is the turn", "how far is my turn", "which way", "which way do i go", "where do i go"].contains(text) {
            return .nextTurn
        }
        if context.walking, ["how far", "how much further", "are we there yet"].contains(text) { return .nextTurn }
        if ["where am i", "what street am i on", "what's my location", "what is my location", "what's the address here"].contains(text) {
            return .whereAmI
        }
        if has(text, ["call my contact", "call my emergency contact", "emergency call", "call for help"]) || ["i need help", "emergency"].contains(text) {
            return .emergencyCall
        }
        if let who = after(text, ["set my emergency contact to ", "make my emergency contact ", "my emergency contact is "]) {
            return who.isEmpty ? nil : .setEmergencyContact(title(who))
        }
        return nil
    }

    // MARK: - Hearing

    private static func hearing(_ text: String) -> AccessCommand? {
        if let on = toggle(text, ["live captions", "captions", "captioning"]) { return .captions(on) }
        if ["caption this", "caption the conversation", "caption this conversation", "live captions"].contains(text) { return .captions(true) }
        if let on = toggle(text, ["sound alerts", "sound recognition", "sound alert"]) { return .soundAlerts(on) }
        if ["listen for sounds", "listen for alarms"].contains(text) { return .soundAlerts(true) }
        if ["what did they say", "what did i miss", "what was said", "what did he say", "what did she say", "read back the captions", "read the captions back"].contains(text) {
            return .whatWasSaid
        }
        if has(text, ["save this conversation", "save the conversation", "save the transcript", "save the captions", "keep this transcript"]) { return .saveTranscript }
        if has(text, ["delete the transcript", "clear the transcript", "clear the captions", "delete the captions", "erase the transcript"]) { return .clearTranscript }
        return nil
    }

    // MARK: - Speech and movement

    private static func speech(_ text: String) -> AccessCommand? {
        if ["speak slower", "talk slower", "slow down", "speak more slowly", "talk more slowly", "slower"].contains(text) { return .pace(.slow) }
        if ["speak faster", "talk faster", "speed up", "speak more quickly", "faster"].contains(text) { return .pace(.fast) }
        if ["normal speed", "speak normally", "talk normally", "normal pace"].contains(text) { return .pace(.normal) }
        if ["give me more time", "wait longer", "i need more time", "i need more time to speak", "more time to speak", "be patient"].contains(text) { return .extraTime(true) }
        if ["normal timing", "don't wait so long", "wait less", "i don't need more time"].contains(text) { return .extraTime(false) }
        if ["what can i say", "what can you do", "help", "list commands", "accessibility help", "what are my commands"].contains(text) { return .help }
        return nil
    }

    // MARK: - Memory and tasks

    private static func tasks(_ text: String, _ loose: String) -> AccessCommand? {
        if let range = loose.range(of: #"(teach|new|save a|create a|make a|add a)\s+(routine|task)\s+(called\s+|named\s+)?"#, options: .regularExpression) {
            let rest = String(loose[range.upperBound...])
            for divider in [":", " the steps are ", " steps are ", " steps ", ", first ", " first "] {
                if let cut = rest.range(of: divider) {
                    let name = clean(String(rest[..<cut.lowerBound]))
                    let steps = Routine.steps(from: String(rest[cut.upperBound...]))
                    guard !name.isEmpty, !steps.isEmpty else { return nil }
                    return .teachRoutine(name: name, steps: steps)
                }
            }
            return nil
        }
        if ["what routines do i have", "list my routines", "list routines", "what tasks do i have", "my routines"].contains(text) { return .listRoutines }
        if let name = after(text, ["delete the ", "forget the ", "remove the ", "delete my ", "forget my "]), name.hasSuffix(" routine") {
            return .deleteRoutine(String(name.dropLast(8)))
        }
        if let name = after(text, ["start my ", "start the ", "begin my ", "begin the ", "do my ", "run my "]), name.hasSuffix(" routine") {
            return .startTask(String(name.dropLast(8)))
        }
        if let name = after(text, ["start routine ", "start task ", "start the task "]) { return .startTask(name) }
        if let name = after(text, ["guide me through ", "walk me through ", "talk me through ", "help me through "]) {
            return .startTask(strip(name, suffixes: [" step by step", " one step at a time"]))
        }
        if text.hasSuffix(" step by step") || text.hasSuffix(" one step at a time") {
            let core = strip(text, suffixes: [" step by step", " one step at a time"])
            if let name = after(core, ["help me ", "how do i ", "show me how to ", "tell me how to "]) { return .startTask(name) }
        }
        return nil
    }

    private static func memory(_ text: String) -> AccessCommand? {
        if ["what was i doing", "what am i doing", "where was i", "what was i up to", "remind me what i was doing", "what was i just doing", "what was i about to do"].contains(text) {
            return .whatWasIDoing
        }
        if let on = toggle(text, ["activity recall"]) { return .recall(on) }
        if ["forget what i was doing", "clear my activity", "forget my activity", "erase my activity"].contains(text) { return .forgetActivity }
        for lead in ["when i see ", "next time i see ", "the next time i see ", "when i meet ", "when i talk to "] {
            guard let rest = after(text, [lead]) else { continue }
            for divider in [" remind me to ", " remind me about ", " remind me that ", " tell me to "] {
                if let cut = rest.range(of: divider) {
                    let person = String(rest[..<cut.lowerBound])
                    let note = String(rest[cut.upperBound...])
                    guard !person.isEmpty, !note.isEmpty else { return nil }
                    return .remindWhenSeeing(person: title(person), note: note)
                }
            }
        }
        if let rest = after(text, ["remind me to ", "remind me about "]) {
            for divider in [" when i see ", " next time i see ", " the next time i see ", " when i meet "] {
                if let cut = rest.range(of: divider) {
                    let note = String(rest[..<cut.lowerBound])
                    let person = String(rest[cut.upperBound...])
                    guard !person.isEmpty, !note.isEmpty else { return nil }
                    return .remindWhenSeeing(person: title(person), note: note)
                }
            }
        }
        return nil
    }

    // MARK: - Matching helpers

    private static func has(_ text: String, _ phrases: [String]) -> Bool {
        let padded = " " + text + " "
        return phrases.contains { padded.contains(" " + $0 + " ") || padded.contains(" " + $0 + "s ") }
    }

    /// The rest of the sentence after the first lead-in it starts with.
    private static func after(_ text: String, _ leads: [String]) -> String? {
        for lead in leads where text.hasPrefix(lead) {
            return String(text.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func strip(_ text: String, suffixes: [String]) -> String {
        for suffix in suffixes where text.hasSuffix(suffix) {
            return String(text.dropLast(suffix.count))
        }
        return text
    }

    /// "turn on X", "X on", "start X", and the same for off, for any of the given names.
    private static func toggle(_ text: String, _ names: [String]) -> Bool? {
        for name in names {
            if ["turn on \(name)", "turn \(name) on", "\(name) on", "start \(name)", "enable \(name)", "switch on \(name)", "start the \(name)", "turn on the \(name)"].contains(text) { return true }
            if ["turn off \(name)", "turn \(name) off", "\(name) off", "stop \(name)", "disable \(name)", "switch off \(name)", "stop the \(name)", "turn off the \(name)", "end \(name)"].contains(text) { return false }
        }
        return nil
    }

    private static func clean(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == " " ? $0 : " " })
            .split(separator: " ").joined(separator: " ")
    }

    private static func title(_ name: String) -> String {
        name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

enum SpeechPace: String, Codable, CaseIterable, Sendable {
    case slow, normal, fast

    /// The factor applied to the voice's normal speaking rate.
    var rate: Float {
        switch self {
        case .slow: return 0.8
        case .normal: return 1
        case .fast: return 1.2
        }
    }
}
