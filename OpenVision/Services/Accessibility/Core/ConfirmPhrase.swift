// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Understands a short yes or no.
//
// Anything that calls someone, saves a face, or deletes several things at once waits for a
// spoken yes. The answer has to be easy to give for a person whose speech is slow, slurred,
// or tiring, so one short word is enough, and the recognizer's usual mishearings of those
// words count. When a reply holds both a yes and a no, it is taken as no.

import Foundation

enum Confirmation: Equatable, Sendable {
    case yes, no, again

    static func parse(_ text: String) -> Confirmation? {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" })
            .map(String.init)
        guard !words.isEmpty, words.count <= 6 else { return nil }
        let phrase = " " + words.joined(separator: " ") + " "
        if noWords.contains(where: { phrase.contains(" \($0) ") }) { return .no }
        // A yes acts, so it has to be short: "turn right at the door" is not consent.
        // Declining is safe at any length up to the limit above.
        if words.count <= 3, againWords.contains(where: { phrase.contains(" \($0) ") }) { return .again }
        if words.count <= 4, yesWords.contains(where: { phrase.contains(" \($0) ") }) { return .yes }
        return nil
    }

    private static let yesWords = [
        "yes", "yeah", "yep", "yup", "yas", "yess", "ya", "ok", "okay", "sure", "confirm", "confirmed",
        "correct", "right", "do it", "go ahead", "please do", "affirmative", "that's right",
    ]
    private static let noWords = [
        "no", "nope", "nah", "know", "don't", "do not", "cancel", "stop", "never mind", "nevermind",
        "negative", "wrong", "not now", "wait",
    ]
    private static let againWords = ["repeat", "again", "say that again", "what", "pardon", "sorry"]
}

/// Something that waits for a yes before it happens.
struct PendingConfirmation<Action: Sendable>: Sendable {
    var action: Action
    /// The question, kept so it can be asked again.
    var question: String
    var askedAt: Date

    /// An unanswered question lapses, so a "yes" said much later to something else does
    /// not trigger it.
    func expired(at now: Date, after seconds: TimeInterval = 45) -> Bool {
        now.timeIntervalSince(askedAt) > seconds
    }
}
