// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The spoken commands of Look to Talk.
//
// Like the rest of the workshop, each is a fixed phrase matched on the phone, and a
// sentence that matches nothing goes on to the assistant as before. With the switch off
// nothing matches at all.

import Foundation

enum LookCommand: Equatable, Sendable {
    /// Turn the camera on and look for a window.
    case start
    /// Look for a window again, keeping any lock until another is found.
    case again
    /// Everything off.
    case stop
    /// Hold the target so the wearer can look away. A name locks without looking.
    case lock(String?)
    case unlock
    case who
    /// The answer to "Talking to Indy?".
    case yes, no
    /// One request for whichever assistant is in view: "ask this one to …".
    case once(String)

    struct Context: Equatable, Sendable {
        /// The switch in Settings.
        var enabled = false
        /// The names of the wearer's assistants.
        var bots: [String] = []
        /// The camera is looking, or a target is held.
        var active = false
        /// A question is waiting for yes or no.
        var asking = false
    }

    static func parse(_ utterance: String, context: Context) -> LookCommand? {
        let said = Said(utterance)
        guard context.enabled, !said.isEmpty else { return nil }

        if context.asking {
            if said.is(["yes", "yeah", "yep", "yes please", "correct", "right", "that's right", "that's it", "it is",
                        "yes it is", "sure", "that one"]) {
                return .yes
            }
            if said.is(["no", "nope", "no thanks", "wrong", "that's wrong", "not that one", "it isn't", "no it isn't",
                        "neither", "cancel"]) {
                return .no
            }
            // A name alone answers the question better than yes or no.
            if let name = bot(said.text, context) { return .lock(name) }
        }

        if said.is(["look to talk", "start look to talk", "begin look to talk", "turn on look to talk",
                    "look to talk on", "switch on look to talk"]) {
            return .start
        }
        if said.is(["stop look to talk", "end look to talk", "turn off look to talk", "look to talk off",
                    "switch off look to talk"]) {
            return .stop
        }
        if said.is(["who am i talking to", "who am i looking at", "who is listening", "who's listening",
                    "which assistant is this", "who is this going to", "who am i locked on to"]) {
            return .who
        }

        for lead in ["lock on to", "lock onto", "lock on", "lock to", "stay with", "switch to", "talk to"] {
            if let rest = said.after([lead]), let name = bot(rest.lowercased(), context) { return .lock(name) }
        }

        let nouns = ["this one", "that one", "this bot", "this assistant", "this window"]
        let leads = ["ask", "tell"].flatMap { verb in
            nouns.flatMap { noun in ["\(verb) \(noun) to", "\(verb) \(noun) that", "\(verb) \(noun)"] }
        }
        if let rest = said.after(leads), !rest.isEmpty {
            return .once(rest)
        }

        guard context.active else { return nil }
        if said.is(["lock on", "lock", "lock it", "lock that", "lock on to this", "lock on to this one", "lock on to that",
                    "stay with this one", "stay on this one", "hold that", "hold this one", "keep this one"]) {
            return .lock(nil)
        }
        if said.is(["unlock", "let go", "release", "release the lock", "lock off", "unlock the assistant", "stop looking"]) {
            return .unlock
        }
        if let rest = said.after(["let go of", "stop talking to", "unlock"]), bot(rest.lowercased(), context) != nil {
            return .unlock
        }
        if said.is(["look again", "look now", "pick again", "choose again", "look at the screen again"]) {
            return .again
        }
        return nil
    }

    /// The assistant a spoken name means. The recognizer may write "Fire Fox" as
    /// "Firefox", so spaces do not count.
    private static func bot(_ spoken: String, _ context: Context) -> String? {
        let wanted = squashed(spoken)
        guard !wanted.isEmpty else { return nil }
        return context.bots.first { squashed($0) == wanted }
    }

    private static func squashed(_ text: String) -> String {
        WorkshopText.words(text).joined()
    }
}
