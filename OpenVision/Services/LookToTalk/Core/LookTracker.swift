// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Turns a run of looks into a choice, the way a pointer turns a run of positions into a
// click.
//
// One look is not a choice. A head sweeps past a screen on its way somewhere else, and
// text recognition is wrong now and then. So a target is taken only when two looks in a
// row agree, or when one look finds something that was put there to be found: a marker
// or a badge. When the looks agree and still are not clear, the wearer is asked, once:
// "Talking to Indy?"
//
// What is held can be held two ways. Followed, it lasts while it stays in view, and the
// camera stays on to see that it does. Locked, it lasts until it is let go, and the
// camera goes off. A lock that is never used again ends by itself, so that a request
// made an hour later does not go to an assistant chosen for something else.
//
// Nothing here touches a camera, a clock, or a speaker. The time comes in with each
// call and what to do comes out, so every rule can be tested.

import Foundation

struct LookTracker: Equatable, Sendable {
    struct Rules: Equatable, Sendable {
        /// Lock on as soon as a target is found, so the camera can go off.
        var autoLock = true
        /// Open the microphone after the tone, as the wake word would.
        var listenAfterTone = true
        /// Looks in a row that must agree. A marker or a badge needs one.
        var dwell = 2
        /// How long a followed target may be out of view before it is let go.
        var grace: TimeInterval = 5
        /// How long a question waits for its answer.
        var askPatience: TimeInterval = 8
        /// After a no, or a question nobody answered, how long that target is left alone.
        var rest: TimeInterval = 45
        /// How long the camera looks for a window before giving up.
        var searchLimit: TimeInterval = 45
        /// How long a target is followed before it is locked to save the battery.
        var followLimit: TimeInterval = 300
        /// How long a lock lasts after it was last used.
        var lockLife: TimeInterval = 600
    }

    enum State: Equatable, Sendable {
        case off
        /// The camera is on and nothing has been found yet.
        case searching
        /// "Talking to Indy?" is waiting for its answer.
        case asking(LookTarget, other: LookTarget?)
        /// Held while it stays in view. The camera is on.
        case following(LookTarget)
        /// Held until it is let go. The camera is off.
        case locked(LookTarget)
    }

    enum Tone: String, Sendable, CaseIterable {
        case found
        case locked
        case released
        case unsure
    }

    enum Effect: Equatable, Sendable {
        case tone(Tone, LookTarget?)
        case say(String)
        /// Open the microphone for the wearer's next sentence: the request, or the answer
        /// to a question.
        case listen
    }

    var rules = Rules()
    private(set) var state = State.off

    /// A lock that is kept while the camera looks again, and comes back if it finds nothing.
    private struct Kept: Equatable, Sendable {
        var target: LookTarget
        var used: Date
    }

    private struct Streak: Equatable, Sendable {
        var target: LookTarget
        var count: Int
    }

    private var kept: Kept?
    private var streak: Streak?
    private var began = Date.distantPast
    private var asked = Date.distantPast
    private var seen = Date.distantPast
    private var used = Date.distantPast
    /// Targets the wearer said no to, and when.
    private var declined: [LookTarget: Date] = [:]
    /// Targets asked about and not answered, and when.
    private var unanswered: [LookTarget: Date] = [:]

    init(rules: Rules = Rules()) {
        self.rules = rules
    }

    // MARK: - What is held

    /// The target requests go to right now. A lock stays in force while the camera
    /// looks again.
    var held: LookTarget? {
        switch state {
        case .following(let target), .locked(let target): return target
        case .searching, .asking: return kept?.target
        case .off: return nil
        }
    }

    /// The camera is needed, so the capture light is on.
    var wantsCamera: Bool {
        switch state {
        case .searching, .asking, .following: return true
        case .off, .locked: return false
        }
    }

    var isOff: Bool { state == .off }

    /// The target a question is waiting on.
    var question: LookTarget? {
        if case .asking(let target, _) = state { return target }
        return nil
    }

    var status: LookStatus {
        switch state {
        case .off: return .off
        case .searching: return .searching(kept: kept?.target.name)
        case .asking(let target, _): return .asking(target.name)
        case .following(let target): return .following(target.name)
        case .locked(let target): return .locked(target.name)
        }
    }

    // MARK: - Commands

    /// "Look to talk", and "look again".
    mutating func start(at now: Date) -> [Effect] {
        switch state {
        case .off:
            begin(at: now)
            return [.say("Look to Talk is on, and the camera light is on. Look at an assistant's window.")]
        case .locked(let target):
            kept = Kept(target: target, used: used)
            begin(at: now)
            return [.say("Looking again, and the camera light is on.")]
        case .following(let target):
            return [.say("You're looking at \(target.name). Say lock on to keep it when you look away.")]
        case .searching, .asking:
            // Asking twice is asking for more time.
            began = now
            return [.say("Still looking. Face the window, or hold its name badge nearer the middle.")]
        }
    }

    private mutating func begin(at now: Date) {
        state = .searching
        began = now
        streak = nil
        declined = [:]
        unanswered = [:]
    }

    /// "Lock on", with or without a name. A name locks without the camera at all.
    mutating func lock(_ named: LookTarget?, at now: Date) -> [Effect] {
        if let named {
            hold(named, at: now)
            return [.tone(.locked, named), .say("Locked on to \(named.name).")]
        }
        switch state {
        case .following(let target), .asking(let target, _):
            hold(target, at: now)
            return [.tone(.locked, target), .say("Locked on to \(target.name).")]
        case .locked(let target):
            return [.say("Already locked on to \(target.name).")]
        case .searching:
            if let kept {
                hold(kept.target, at: now)
                return [.say("Still locked on to \(kept.target.name).")]
            }
            return [.say("I'm not looking at an assistant yet. Say lock on to, and a name.")]
        case .off:
            return [.say("Look to Talk is off. Say look to talk, or say lock on to, and a name.")]
        }
    }

    private mutating func hold(_ target: LookTarget, at now: Date) {
        state = .locked(target)
        used = now
        kept = nil
        streak = nil
    }

    /// "Let go", and "stop look to talk". Everything ends.
    mutating func release() -> [Effect] {
        let target = held
        let wasOff = isOff
        state = .off
        kept = nil
        streak = nil
        if let target { return [.tone(.released, target), .say("Let go of \(target.name).")] }
        return [.say(wasOff ? "Look to Talk is already off." : "Look to Talk is off.")]
    }

    /// Yes or no to the question that is waiting.
    mutating func answer(_ yes: Bool, at now: Date) -> [Effect] {
        guard case .asking(let target, let other) = state else { return [] }
        if yes { return take(target, at: now) }
        declined[target] = now
        if let other, !rests(other, at: now) {
            state = .asking(other, other: nil)
            asked = now
            return [.tone(.unsure, other), .say("\(other.name)?"), .listen]
        }
        state = .searching
        began = now
        streak = nil
        return [.say("OK. Look at the window again, or say lock on to, and a name.")]
    }

    /// A request went to the held target, so its lock is still wanted.
    mutating func used(at now: Date) {
        if case .locked = state { used = now }
        kept?.used = now
    }

    // MARK: - Looks

    /// Takes what one look found.
    mutating func looked(_ reading: LookReading, at now: Date) -> [Effect] {
        switch state {
        case .off, .locked:
            return []

        case .following(let target):
            if reading.stillShows(target) { seen = now }
            // Another window takes over only when it is clear, and clearer than this one.
            let verdict = reading.verdict { $0 != target && !self.rests($0, at: now) }
            guard case .sure(let other, let deliberate) = verdict,
                  reading.score(of: other) - reading.score(of: target) >= LookReading.margin else {
                streak = nil
                return []
            }
            guard counted(other) >= rules.dwell || deliberate else { return [] }
            return take(other, at: now)

        case .searching, .asking:
            switch reading.verdict(allowing: { !self.rests($0, at: now) }) {
            case .nothing:
                streak = nil
                return []
            case .sure(let target, let deliberate):
                guard counted(target) >= rules.dwell || deliberate else { return [] }
                return take(target, at: now)
            case .unsure(let target, let other):
                // One question at a time, and not the same one twice in a row.
                guard counted(target) >= rules.dwell, state == .searching,
                      !recent(unanswered[target], at: now) else { return [] }
                state = .asking(target, other: other)
                asked = now
                // A question needs its answer heard, whatever the setting for after a tone.
                return [.tone(.unsure, target), .say("Talking to \(target.name)?"), .listen]
            }
        }
    }

    /// Moves time on. Call it about once a second while anything is held or looked for.
    mutating func tick(at now: Date) -> [Effect] {
        switch state {
        case .off:
            return []

        case .searching:
            guard now.timeIntervalSince(began) > rules.searchLimit else { return [] }
            if let kept {
                state = .locked(kept.target)
                used = kept.used
                self.kept = nil
                return [.say("I can't see another assistant's window. Still locked on to \(kept.target.name).")]
            }
            state = .off
            return [
                .tone(.released, nil),
                .say("I can't see an assistant's window, so Look to Talk is off. A name badge helps. Or say lock on to, and a name."),
            ]

        case .asking(let target, _):
            guard now.timeIntervalSince(asked) > rules.askPatience else { return [] }
            // Silence is not a no. A clear look at the same window can still take it.
            unanswered[target] = now
            state = .searching
            streak = nil
            return []

        case .following(let target):
            if now.timeIntervalSince(seen) > rules.grace {
                state = .searching
                began = now
                streak = nil
                return [.tone(.released, target)]
            }
            if now.timeIntervalSince(began) > rules.followLimit {
                hold(target, at: now)
                return [.tone(.locked, target), .say("The camera is off to save the battery. Still locked on to \(target.name).")]
            }
            return []

        case .locked(let target):
            guard now.timeIntervalSince(used) > rules.lockLife else { return [] }
            state = .off
            return [.tone(.released, target), .say("Let go of \(target.name).")]
        }
    }

    /// The camera stopped and would not come back.
    mutating func lostCamera() -> [Effect] {
        guard wantsCamera else { return [] }
        streak = nil
        if let kept {
            state = .locked(kept.target)
            used = kept.used
            self.kept = nil
            return [.say("I've lost the glasses camera. Still locked on to \(kept.target.name).")]
        }
        state = .off
        return [.tone(.released, nil), .say("I've lost the glasses camera, so Look to Talk is off.")]
    }

    // MARK: - Helpers

    private mutating func take(_ target: LookTarget, at now: Date) -> [Effect] {
        kept = nil
        streak = nil
        var effects: [Effect]
        if rules.autoLock {
            state = .locked(target)
            used = now
            effects = [.tone(.locked, target), .say("\(target.name), locked.")]
        } else {
            state = .following(target)
            began = now
            seen = now
            effects = [.tone(.found, target), .say("\(target.name).")]
        }
        if rules.listenAfterTone { effects.append(.listen) }
        return effects
    }

    /// Counts a look at a target, and returns how many in a row that makes.
    private mutating func counted(_ target: LookTarget) -> Int {
        let count = streak?.target == target ? (streak?.count ?? 0) + 1 : 1
        streak = Streak(target: target, count: count)
        return count
    }

    /// The wearer said no to this target a moment ago.
    private func rests(_ target: LookTarget, at now: Date) -> Bool {
        recent(declined[target], at: now)
    }

    private func recent(_ date: Date?, at now: Date) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) < rules.rest
    }
}

/// What Look to Talk is doing, for the phone's screen and for "who am I talking to".
enum LookStatus: Equatable, Sendable {
    case off
    case searching(kept: String?)
    case asking(String)
    case following(String)
    case locked(String)

    /// A few words for a chip on the home screen.
    var title: String {
        switch self {
        case .off: return "Look to Talk is off"
        case .searching(let kept?): return "Looking again. Still \(kept)"
        case .searching(nil): return "Looking for a window"
        case .asking(let name): return "Talking to \(name)?"
        case .following(let name): return "Looking at \(name)"
        case .locked(let name): return "Locked on to \(name)"
        }
    }

    /// The SF Symbol beside the title.
    var symbol: String {
        switch self {
        case .off: return "eye.slash"
        case .searching: return "eye"
        case .asking: return "questionmark.circle"
        case .following: return "eye.fill"
        case .locked: return "lock.fill"
        }
    }

    /// The assistant requests go to, when there is one.
    var name: String? {
        switch self {
        case .off, .asking, .searching(nil): return nil
        case .searching(let kept?): return kept
        case .following(let name), .locked(let name): return name
        }
    }

    var cameraOn: Bool {
        switch self {
        case .searching, .asking, .following: return true
        case .off, .locked: return false
        }
    }

    /// The answer to "who am I talking to?".
    func spoken(usual: String) -> String {
        switch self {
        case .off:
            return "Nobody in particular. Requests go to \(usual), as usual."
        case .searching(let kept?):
            return "I'm looking for another window. Until I find one, you're still locked on to \(kept)."
        case .searching(nil):
            return "I'm still looking for an assistant's window. Until I find one, requests go to \(usual)."
        case .asking(let name):
            return "I think you're looking at \(name). Say yes or no."
        case .following(let name):
            return "You're looking at \(name). Say lock on to keep it when you look away."
        case .locked(let name):
            return "You're locked on to \(name). Say let go to release it."
        }
    }
}
