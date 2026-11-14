// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Decides what Guide mode says about what the camera sees, and what it keeps quiet about.
//
// A guide that names everything in view is useless within a minute: the wearer stops
// listening. This file ranks what was seen, says the most pressing one or two, and stays
// silent about anything it has already said until it changes or enough time has passed.

import Foundation

/// One thing the camera found in a frame.
struct Sighting: Equatable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case vehicle, stairs, crossing, obstacle, person, door, animal, sign
    }

    var kind: Kind
    /// Where it is in the frame. Nil when only its presence is known, which is the case
    /// for whole-frame labels such as "stairs".
    var box: FrameBox?
    /// A name to say in place of the kind: "dog", "bus", or the words on a sign.
    var label: String?

    init(_ kind: Kind, box: FrameBox? = nil, label: String? = nil) {
        self.kind = kind
        self.box = box
        self.label = label
    }
}

/// Where something is, as the wearer would turn their head to face it.
enum Side: String, Sendable {
    case left, slightlyLeft, ahead, slightlyRight, right

    init(midX: Double) {
        switch midX {
        case ..<0.2: self = .left
        case ..<0.4: self = .slightlyLeft
        case ..<0.6: self = .ahead
        case ..<0.8: self = .slightlyRight
        default: self = .right
        }
    }

    var spoken: String {
        switch self {
        case .left: return "on your left"
        case .slightlyLeft: return "slightly left"
        case .ahead: return "ahead"
        case .slightlyRight: return "slightly right"
        case .right: return "on your right"
        }
    }

    /// Stereo position for an audio cue, from -1 (left ear) to 1 (right ear).
    var pan: Float {
        switch self {
        case .left: return -1
        case .slightlyLeft: return -0.5
        case .ahead: return 0
        case .slightlyRight: return 0.5
        case .right: return 1
        }
    }
}

struct Callout: Equatable, Sendable {
    var text: String
    /// Nil when the position is unknown.
    var side: Side?
    /// True for something to react to now: a vehicle, stairs, or anything very close.
    var urgent: Bool
}

struct GuideNarrator: Sendable {
    /// How long before the same thing in the same place is mentioned again.
    var repeatAfter: TimeInterval = 8
    /// The most callouts spoken for one frame.
    var limit = 2

    private var said: [String: (at: Date, near: Bool)] = [:]

    init() {}

    /// The callouts worth saying for this frame, most pressing first.
    mutating func callouts(for sightings: [Sighting], at now: Date) -> [Callout] {
        var groups: [String: Group] = [:]
        for sighting in sightings {
            let side = sighting.box.map { Side(midX: $0.midX) }
            let name = (sighting.label ?? sighting.kind.rawValue).lowercased()
            let key = "\(sighting.kind.rawValue)|\(name)|\(side?.rawValue ?? "")"
            var group = groups[key] ?? Group(kind: sighting.kind, name: name, side: side)
            group.count += 1
            group.near = group.near || Self.isNear(sighting)
            groups[key] = group
        }

        var fresh: [(key: String, group: Group)] = []
        for (key, group) in groups {
            if let last = said[key] {
                // Said recently, and it has not come closer since: stay quiet.
                let cameCloser = group.near && !last.near
                if now.timeIntervalSince(last.at) < repeatAfter && !cameCloser { continue }
            }
            fresh.append((key, group))
        }
        fresh.sort { lhs, rhs in
            let left = lhs.group.rank, right = rhs.group.rank
            return left == right ? lhs.key < rhs.key : left < right
        }
        let chosen = fresh.prefix(limit)
        for item in chosen { said[item.key] = (now, item.group.near) }
        // Forget what has been out of view for a while, so the table does not grow all walk.
        said = said.filter { now.timeIntervalSince($0.value.at) < repeatAfter * 4 }
        return chosen.map { $0.group.callout }
    }

    /// A person or object whose box fills most of the frame height is within a few steps.
    private static func isNear(_ sighting: Sighting) -> Bool {
        guard let box = sighting.box else { return false }
        return box.height > 0.7 || box.width > 0.6
    }

    private struct Group {
        var kind: Sighting.Kind
        var name: String
        var side: Side?
        var count = 0
        var near = false

        /// Lower is said first. Moving vehicles and level changes outrank everything.
        var rank: Int {
            switch kind {
            case .vehicle: return near ? 0 : 1
            case .stairs: return 2
            case .crossing: return 3
            case .obstacle: return near ? 3 : 5
            case .person: return near ? 4 : 7
            case .door: return 6
            case .animal: return 6
            case .sign: return 8
            }
        }

        var callout: Callout {
            let urgent = kind == .vehicle || kind == .stairs || near
            var words: String
            switch kind {
            case .sign:
                words = "Sign: \(name)"
            case .person where count > 1:
                words = "\(Self.number(count)) people"
            case .person:
                words = "Person"
            default:
                words = count > 1 ? "\(Self.number(count)) \(Self.plural(name))" : name.prefix(1).uppercased() + name.dropFirst()
            }
            if near { words += ", close" }
            if let side { words += ", \(side.spoken)" }
            else if kind != .sign { words += " in view" }
            return Callout(text: words + ".", side: side, urgent: urgent)
        }

        private static func plural(_ name: String) -> String {
            if name.hasSuffix("s") { return name.hasSuffix("ss") || name.hasSuffix("us") ? name + "es" : name }
            if name.hasSuffix("x") || name.hasSuffix("ch") || name.hasSuffix("sh") { return name + "es" }
            return name + "s"
        }

        private static func number(_ count: Int) -> String {
            let words = ["Two", "Three", "Four", "Five"]
            return count >= 2 && count <= 5 ? words[count - 2] : "Several"
        }
    }
}

/// The spoken answer to "where's the door?": only the sightings that match what was asked for.
enum ObjectFinder {
    static func answer(for wanted: String, in sightings: [Sighting]) -> String? {
        let target = wanted.lowercased()
        let matches = sightings.filter { sighting in
            let names = [sighting.kind.rawValue, sighting.label?.lowercased() ?? ""]
            return names.contains { !$0.isEmpty && ($0.contains(target) || target.contains($0)) }
        }
        guard let first = matches.first else { return nil }
        let name = first.kind == .sign ? "A sign that says \(first.label ?? target)" : "The \(first.label?.lowercased() ?? target)"
        guard let box = first.box else { return "\(name) is in view, but I can't tell which side. Turn slowly and ask again." }
        let near = box.height > 0.7 || box.width > 0.6
        return "\(name) is \(Side(midX: box.midX).spoken)\(near ? ", close" : "")."
    }
}
