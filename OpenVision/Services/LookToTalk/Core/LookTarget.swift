// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Look to Talk: looking chooses, the voice acts.
//
// The wearer looks at a screen. The glasses camera sees it, the phone reads what is on
// it, and whatever was recognized becomes the target of the next thing said. Today the
// only kind of target is an assistant's chat window, and holding one means requests go
// to that assistant without its name being said.
//
// The kinds are kept apart from the rest on purpose. A document, a browser tab, or a
// shop's order page is a new `Kind`, a reader that finds it in a `ScreenView`, and a
// decision about what holding it means: most likely "send this to the assistant I am
// talking to", not "talk to this". The tracker, the tones, and the spoken commands do
// not know which kind they are handling, and do not need to change.

import Foundation

/// Something on a screen that can be chosen by looking at it.
struct LookTarget: Hashable, Sendable {
    enum Kind: String, Sendable {
        /// An assistant's chat window. Holding it chooses who hears the next request.
        case assistant
    }

    var kind: Kind
    /// For an assistant, its name as it is on the roster.
    var name: String

    static func assistant(_ name: String) -> LookTarget {
        LookTarget(kind: .assistant, name: name)
    }
}

/// A QR code or other machine-readable code in view.
struct CodeSighting: Equatable, Sendable {
    var payload: String
    var box: FrameBox
}

/// What one look at a screen gave: the text and the codes found, and where each was.
///
/// The picture itself is not part of it. Once the phone has read a frame, the frame is
/// dropped, and nothing that follows can keep it or send it.
struct ScreenView: Equatable, Sendable {
    var text: [TextFragment] = []
    var codes: [CodeSighting] = []
}

/// The names an assistant's window may show: its own, and any others the wearer gave,
/// such as the handle its chat app uses.
struct LookName: Equatable, Sendable {
    var bot: String
    var others: [String] = []

    var all: [String] { [bot] + others }
}

/// One thing a look may have found, and how strongly.
struct LookCandidate: Equatable, Sendable {
    enum Evidence: String, Sendable {
        /// A code made for this: it says which assistant, and nothing else looks like it.
        case marker
        /// The words "talk to" and the name, alone on a line.
        case badge
        /// The name alone, or in a short line such as a window title.
        case title
        /// The name inside a longer line of text.
        case mention
    }

    var target: LookTarget
    /// From 0 to 1.
    var score: Double
    var evidence: Evidence
    var box: FrameBox

    /// A marker or a badge was put there to be found, so one look at it is enough.
    var isDeliberate: Bool { evidence == .marker || evidence == .badge }
}

/// What one look amounts to.
enum LookVerdict: Equatable, Sendable {
    case nothing
    /// Clear enough to act on. `deliberate` is true for a marker or a badge.
    case sure(LookTarget, deliberate: Bool)
    /// Something is there, and it is not clear enough to act on without asking.
    case unsure(LookTarget, other: LookTarget?)
}

/// Everything one look found, best first, one entry for each target.
struct LookReading: Equatable, Sendable {
    /// At or above this, a candidate is taken without asking.
    static let sureScore = 0.72
    /// Below this, a candidate is ignored.
    static let askScore = 0.42
    /// The best candidate must lead the next by this much to be taken without asking.
    static let margin = 0.15

    var candidates: [LookCandidate]

    static let empty = LookReading(candidates: [])

    init(candidates: [LookCandidate]) {
        self.candidates = candidates.sorted { $0.score > $1.score }
    }

    func score(of target: LookTarget) -> Double {
        candidates.first { $0.target == target }?.score ?? 0
    }

    /// Whether a target is still plausibly in view, which is all that is asked of a
    /// target already held.
    func stillShows(_ target: LookTarget) -> Bool {
        score(of: target) >= Self.askScore
    }

    /// The verdict among the candidates that pass `allowed`. A target the wearer just
    /// said no to is left out, so the next best gets its turn.
    func verdict(allowing allowed: (LookTarget) -> Bool = { _ in true }) -> LookVerdict {
        let open = candidates.filter { $0.score >= Self.askScore && allowed($0.target) }
        guard let best = open.first else { return .nothing }
        let next = open.dropFirst().first
        let clear = next.map { best.score - $0.score >= Self.margin } ?? true
        if best.isDeliberate {
            // Two badges side by side and the head pointed between them.
            if let next, next.isDeliberate, !clear { return .unsure(best.target, other: next.target) }
            return .sure(best.target, deliberate: true)
        }
        if best.score >= Self.sureScore, clear { return .sure(best.target, deliberate: false) }
        return .unsure(best.target, other: next?.target)
    }
}
