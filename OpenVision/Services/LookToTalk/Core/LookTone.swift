// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The sounds of Look to Talk: found, locked, let go, and not sure.
//
// The glasses have no vibration motor, so a choice made by looking is confirmed in the
// ear. Each is a few short notes, and they differ in shape so they can be told apart
// without thinking: two rising notes for found, three for locked, two falling for let
// go, and a small step up that slides, like a question, for not sure.
//
// Each assistant has its own starting note, by its place on the roster. After a few
// days the wearer knows who was chosen before the name is spoken.

import Foundation

enum LookTone {
    /// Starting notes, a five-note scale from C5, so any two sound right together.
    static let roots: [Double] = [523.25, 587.33, 659.25, 783.99, 880.0]

    /// - Parameter place: The assistant's place on the roster, from zero. Nil when the
    ///   tone is not about one assistant.
    static func segments(_ tone: LookTracker.Tone, place: Int?) -> [CueTone.Segment] {
        let root = roots[max(0, place ?? 0) % roots.count]
        let gap = CueTone.Segment(startHertz: 0, endHertz: 0, seconds: 0.03)
        func note(_ ratio: Double, _ seconds: Double) -> CueTone.Segment {
            CueTone.Segment(startHertz: root * ratio, endHertz: root * ratio, seconds: seconds)
        }
        switch tone {
        case .found:
            return [note(1, 0.09), gap, note(1.5, 0.13)]
        case .locked:
            return [note(1, 0.08), gap, note(1.5, 0.08), gap, note(2, 0.16)]
        case .released:
            return [note(1.5, 0.09), gap, note(1, 0.15)]
        case .unsure:
            return [
                note(1, 0.09), gap,
                CueTone.Segment(startHertz: root * 1.122, endHertz: root * 1.26, seconds: 0.15),
            ]
        }
    }

    static func wav(_ tone: LookTracker.Tone, place: Int?) -> Data {
        CueTone.wav(CueTone.samples(segments(tone, place: place), volume: 0.4))
    }
}
