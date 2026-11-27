// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The parts of glasses input that can be reasoned about without glasses: sorting out a
// double press of the capture button, reading a nod or a shake of the head from the
// motion sensors, and deciding whether a sentence the glasses heard is a command.

import Foundation

// MARK: - Capture button

/// Sorts out the capture button's presses.
///
/// Current glasses firmware reports a double press as a short press followed by a double
/// press. Acting on the short press at once would take a picture on the way to every
/// double press. So a short press is held for a moment: a double press that follows
/// replaces it, and otherwise it is released when the moment has passed.
struct CapturePressBuffer: Sendable {
    /// How long a short press waits for a double press to follow it.
    static let wait: TimeInterval = 0.45

    private var heldAt: TimeInterval?

    init() {}

    /// When the held short press should be released by calling `release(at:)`.
    var deadline: TimeInterval? { heldAt.map { $0 + Self.wait } }

    /// Takes one press from the glasses. Returns the presses to act on now, in order.
    mutating func take(_ press: GestureSignal.Press, at time: TimeInterval) -> [GestureSignal.Press] {
        var out: [GestureSignal.Press] = []
        if let held = heldAt, time - held >= Self.wait {
            out.append(.short)
            heldAt = nil
        }
        switch press {
        case .short:
            if heldAt != nil { out.append(.short) }
            heldAt = time
        case .double:
            heldAt = nil
            out.append(.double)
        case .hold:
            if heldAt != nil {
                out.append(.short)
                heldAt = nil
            }
            out.append(.hold)
        }
        return out
    }

    /// Releases the held short press once its wait is over.
    mutating func release(at time: TimeInterval) -> GestureSignal.Press? {
        guard let held = heldAt, time - held >= Self.wait else { return nil }
        heldAt = nil
        return .short
    }
}

// MARK: - Head gestures

/// One reading from the glasses' motion sensors.
struct HeadMotion: Sendable {
    struct Vector: Equatable, Sendable {
        var x: Double
        var y: Double
        var z: Double

        static let zero = Vector(x: 0, y: 0, z: 0)

        var length: Double { (x * x + y * y + z * z).squareRoot() }
        var unit: Vector? {
            let length = self.length
            return length > 1e-9 ? self * (1 / length) : nil
        }
        func dot(_ other: Vector) -> Double { x * other.x + y * other.y + z * other.z }
        static func + (a: Vector, b: Vector) -> Vector { Vector(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Vector, b: Vector) -> Vector { Vector(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        static func * (a: Vector, k: Double) -> Vector { Vector(x: a.x * k, y: a.y * k, z: a.z * k) }
    }

    /// Seconds, on any clock that only moves forward.
    var time: TimeInterval
    /// How fast the head is turning about each of the sensor's axes, in radians a second.
    var turning: Vector
    /// The accelerometer, in metres per second squared. It includes gravity, which is how
    /// the detector knows which way is down. Nil when the glasses sent no reading.
    var acceleration: Vector?
}

enum HeadAnswer: String, Equatable, Sendable {
    case yes
    case no
}

/// Reads "yes" from two nods and "no" from a shake of the head.
///
/// A shake turns the head about the vertical. A nod turns it about a level axis. Which
/// way is vertical comes from gravity, not from the sensor's own axes, so the answer does
/// not depend on how the sensor sits in the frame. That matters: current firmware reports
/// motion turned a quarter turn on glasses without a display.
///
/// An answer needs three quick swings that alternate in direction: down, up, down for a
/// nod, or left, right, left for a shake. One glance to the side or one look down at the
/// ground is two swings at most, and walking does not turn the head fast enough to count.
struct HeadGestureDetector: Sendable {
    /// A swing counts when the head turns at least this fast, in radians a second. That
    /// is about 50 degrees a second, several times what walking does.
    static let swingSpeed = 0.9
    /// One kind of turning must be this many times stronger than the other to count, so
    /// a diagonal toss of the head is neither answer.
    static let dominance = 1.6
    /// The longest gap between one swing and the next.
    static let longestGap: TimeInterval = 0.55
    /// The longest a whole gesture may take.
    static let longestGesture: TimeInterval = 1.6
    static let swingsNeeded = 3

    private enum Channel: Sendable { case shake, nod }
    private struct Swing: Sendable {
        var channel: Channel
        var positive: Bool
        var began: TimeInterval
        var ended: TimeInterval
    }

    private var gravity: HeadMotion.Vector?
    private var settled = 0
    private var nodAxis: HeadMotion.Vector?
    private var swings: [Swing] = []

    init() {}

    /// Forgets any gesture in progress. Which way is down is kept.
    mutating func reset() {
        swings = []
        nodAxis = nil
    }

    /// Takes one reading. Returns an answer when this reading completes a gesture.
    mutating func take(_ sample: HeadMotion) -> HeadAnswer? {
        if let acceleration = sample.acceleration {
            // A slow average follows gravity and ignores the jolts of the gesture itself.
            gravity = gravity.map { $0 * 0.92 + acceleration * 0.08 } ?? acceleration
            settled += 1
        }
        // Until there have been a few readings, "down" is a guess.
        guard settled >= 5, let down = gravity?.unit else { return nil }

        if let last = swings.last, sample.time - last.ended > Self.longestGap { reset() }

        let aboutVertical = sample.turning.dot(down)
        let level = sample.turning - down * aboutVertical
        let levelSpeed = level.length
        let verticalSpeed = abs(aboutVertical)

        let channel: Channel
        let positive: Bool
        if verticalSpeed >= Self.swingSpeed, verticalSpeed > levelSpeed * Self.dominance {
            channel = .shake
            positive = aboutVertical > 0
        } else if levelSpeed >= Self.swingSpeed, levelSpeed > verticalSpeed * Self.dominance, let direction = level.unit {
            channel = .nod
            // The first swing fixes the axis of the nod. Later swings are measured along
            // it, so a head that rolls about a different axis does not count as nodding.
            let axis = nodAxis ?? direction
            let along = level.dot(axis)
            guard abs(along) >= Self.swingSpeed * 0.8 else { return nil }
            if nodAxis == nil { nodAxis = axis }
            positive = along > 0
        } else {
            return nil
        }

        if let last = swings.last {
            if last.channel != channel {
                // A different kind of turning starts a new gesture. A nod that starts
                // here fixed its axis just above, and that axis is kept.
                let axis = channel == .nod ? nodAxis : nil
                reset()
                nodAxis = axis
                swings = [Swing(channel: channel, positive: positive, began: sample.time, ended: sample.time)]
                return nil
            }
            if last.positive == positive {
                // Still the same swing. The gap to the next is measured from where it ends.
                swings[swings.count - 1].ended = sample.time
                return nil
            }
        }
        swings.append(Swing(channel: channel, positive: positive, began: sample.time, ended: sample.time))

        guard swings.count >= Self.swingsNeeded, let first = swings.first else { return nil }
        let took = sample.time - first.began
        let answer: HeadAnswer = channel == .nod ? .yes : .no
        reset()
        return took <= Self.longestGesture ? answer : nil
    }
}

/// Which answers a movement of the head may give to the question that is waiting.
///
/// A shake is always accepted, because "no" does nothing. A nod is accepted only for a
/// change to the wearer's own lists that they asked for a moment ago. People nod at each
/// other all day, and the glasses cannot tell who a nod was for, so a yes that places a
/// call, saves or erases a face, starts Guide mode, or lets an assistant act has to be
/// spoken.
enum HeadAnswerPolicy: Equatable, Sendable {
    /// No question is waiting.
    case none
    /// A question is waiting whose yes must be spoken.
    case noOnly
    case yesOrNo

    func accepts(_ answer: HeadAnswer) -> Bool {
        switch self {
        case .none: return false
        case .noOnly: return answer == .no
        case .yesOrNo: return true
        }
    }
}

// MARK: - Restarting what stops by itself

/// Paces the restarts of a capability that the glasses stop by themselves.
///
/// Speech on the glasses stops after about a minute of silence, which is normal, and is
/// started again almost at once. A capability that stops as soon as it starts is broken
/// for now, and each new try waits twice as long as the last so the glasses are not kept
/// busy failing.
struct RestartPacer: Sendable {
    static let shortest: TimeInterval = 2
    static let longest: TimeInterval = 120
    /// A run at least this long was a working one.
    static let healthyRun: TimeInterval = 30

    private var wait = RestartPacer.shortest
    private var startedAt: TimeInterval?

    init() {}

    mutating func started(at time: TimeInterval) {
        startedAt = time
    }

    /// How long to wait before starting again, for a stop at `time`.
    mutating func stopped(at time: TimeInterval) -> TimeInterval {
        let ran = startedAt.map { time - $0 } ?? 0
        startedAt = nil
        if ran >= Self.healthyRun {
            wait = Self.shortest
            return wait
        }
        let now = wait
        wait = min(wait * 2, Self.longest)
        return now
    }
}

// MARK: - Speech heard by the glasses

/// Decides whether a sentence the glasses turned into text is a command for Phoenix Fox.
///
/// The glasses hear everyone near the wearer. A sentence is a command only when it starts
/// with the wake word, the same rule the phone's microphone follows. While the phone is
/// listening it hears the same sentence, so the glasses' copy is dropped and the request
/// runs once.
enum GlassesSpeechGate {
    /// How many characters may come before the wake word: "uh, hey Phoenix" is fine, and
    /// a sentence that only mentions the name is not a command.
    static let leeway = 12

    enum Heard: Equatable, Sendable {
        /// Not for Phoenix Fox.
        case nothing
        /// The wake word and nothing after it: the wearer wants to be listened to.
        case wake
        /// The wake word and then a command.
        case command(String)
    }

    /// The command that follows the wake word, or nil when the sentence is not for
    /// Phoenix Fox or holds only the wake word.
    static func command(in transcript: String, wakeWord: String, phoneListening: Bool) -> String? {
        if case .command(let command) = hear(transcript, wakeWord: wakeWord, phoneListening: phoneListening) {
            return command
        }
        return nil
    }

    static func hear(_ transcript: String, wakeWord: String, phoneListening: Bool) -> Heard {
        guard !phoneListening else { return .nothing }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let word = wakeWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, !word.isEmpty else { return .nothing }
        let lower = text.lowercased()
        guard let found = lower.range(of: word),
              lower.distance(from: lower.startIndex, to: found.lowerBound) <= leeway else { return .nothing }
        // The wake word must be a whole word: "Hey Phoenix" and not "Hey Phoenixes".
        if found.upperBound < lower.endIndex, lower[found.upperBound].isLetter { return .nothing }
        if found.lowerBound > lower.startIndex, lower[lower.index(before: found.lowerBound)].isLetter { return .nothing }
        // Lowercasing can change a string's length in rare scripts, so the cut is made by
        // counting characters and not by reusing the index.
        let skipped = lower.distance(from: lower.startIndex, to: found.upperBound)
        guard skipped <= text.count else { return .nothing }
        let rest = text.dropFirst(skipped)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return rest.isEmpty ? .wake : .command(rest)
    }
}

// MARK: - What a session problem means for the wearer

/// The reasons a session with the glasses can fail, by the toolkit's own names, and what
/// to tell the wearer. Kept apart from the toolkit so the wording can be tested.
enum SessionTrouble: String, Sendable, CaseIterable {
    case noEligibleDevice
    case sessionAlreadyExists
    case thermal
    case power
    case glassesAppUpdateRequired
    case metaAIUnavailable
    case phoneAppTooOld
    case firmwareUpdateRequired
    case other

    /// What the wearer can do, in one or two sentences that can be read aloud.
    var advice: String {
        switch self {
        case .noEligibleDevice:
            return "The glasses are not in reach. Put them on, open the arms, and check that Bluetooth is on."
        case .sessionAlreadyExists:
            return "The glasses are still finishing the last thing. Try again in a moment."
        case .thermal:
            return "The glasses are too hot for the camera. Give them a few minutes to cool."
        case .power:
            return "The glasses' battery is too low for the camera. Charge them and try again."
        case .glassesAppUpdateRequired:
            return "The glasses need their part of Phoenix Fox updated. Open Glasses in Settings and choose Update the glasses app."
        case .metaAIUnavailable:
            return "The Meta AI app is not answering. Open it once, check the glasses are connected there, and try again."
        case .phoneAppTooOld:
            return "These glasses need a newer Phoenix Fox. Update the app."
        case .firmwareUpdateRequired:
            return "The glasses need a software update. Open Glasses in Settings and choose Update the glasses."
        case .other:
            return "The glasses did not start. Try again, and if it keeps happening, fold and reopen them."
        }
    }

    /// Whether trying again by itself could work.
    var worthRetrying: Bool {
        switch self {
        case .sessionAlreadyExists, .noEligibleDevice, .other: return true
        default: return false
        }
    }
}
