// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// One look for one request: "ask this one to check the build".
//
// Nothing is held afterwards. The camera reads a few frames, and the request goes to the
// window they agree on. A request sent to the wrong assistant cannot be taken back, so
// anything short of clear is asked about first, and the yes to that question has to be
// spoken.

import Foundation

struct LookOnce: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// Clear. Send the request.
        case send(LookTarget)
        /// Ask "Send that to Indy?" before sending.
        case ask(LookTarget)
        case nothing
    }

    /// How many frames are read before settling for the best guess.
    static let looks = 4

    private var count = 0
    private var last: LookTarget?
    private var agreed = 0
    private var best: LookCandidate?

    init() {}

    /// Takes what one frame showed. Nil means look again.
    mutating func looked(_ reading: LookReading) -> Outcome? {
        count += 1
        switch reading.verdict() {
        case .sure(let target, let deliberate):
            agreed = last == target ? agreed + 1 : 1
            last = target
            note(reading, target)
            if deliberate || agreed >= 2 { return .send(target) }
        case .unsure(let target, _):
            last = nil
            agreed = 0
            note(reading, target)
        case .nothing:
            last = nil
            agreed = 0
        }
        guard count >= Self.looks else { return nil }
        return best.map { .ask($0.target) } ?? .nothing
    }

    private mutating func note(_ reading: LookReading, _ target: LookTarget) {
        guard let candidate = reading.candidates.first(where: { $0.target == target }) else { return }
        if candidate.score > (best?.score ?? 0) { best = candidate }
    }
}
