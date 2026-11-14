// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Short tones that say where something is before the words arrive.
//
// The glasses have no vibration motor, so direction is carried by sound. While the
// microphone is open, Bluetooth plays in mono and a left or right pan is lost. Each cue
// therefore also carries its direction in its pitch: falling means left, rising means
// right, level means ahead. A cue for something urgent plays twice.

import Foundation

enum CueTone {
    struct Segment: Equatable, Sendable {
        var startHertz: Double
        var endHertz: Double
        var seconds: Double
    }

    static func segments(side: Side?, urgent: Bool) -> [Segment] {
        let low = 520.0, mid = 740.0, high = 1040.0
        let one: Segment
        switch side {
        case .left, .slightlyLeft: one = Segment(startHertz: high, endHertz: low, seconds: 0.14)
        case .right, .slightlyRight: one = Segment(startHertz: low, endHertz: high, seconds: 0.14)
        case .ahead, nil: one = Segment(startHertz: mid, endHertz: mid, seconds: 0.14)
        }
        let gap = Segment(startHertz: 0, endHertz: 0, seconds: 0.06)
        return urgent ? [one, gap, one] : [one]
    }

    /// Mono samples from -1 to 1. Each tone fades in and out over a few milliseconds, so it
    /// does not click in the speaker.
    static func samples(_ segments: [Segment], rate: Double = 22_050, volume: Double = 0.5) -> [Float] {
        var samples: [Float] = []
        for segment in segments {
            let count = Int(segment.seconds * rate)
            guard segment.startHertz > 0 else {
                samples.append(contentsOf: [Float](repeating: 0, count: count))
                continue
            }
            let fade = max(1, Int(0.008 * rate))
            var phase = 0.0
            for index in 0..<count {
                let progress = Double(index) / Double(max(1, count - 1))
                let hertz = segment.startHertz + (segment.endHertz - segment.startHertz) * progress
                phase += 2 * Double.pi * hertz / rate
                let edge = min(1, Double(min(index, count - 1 - index)) / Double(fade))
                samples.append(Float(sin(phase) * volume * edge))
            }
        }
        return samples
    }

    /// The samples as a 16-bit mono WAV file, which the system audio player reads directly.
    static func wav(_ samples: [Float], rate: Int = 22_050) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + bytes)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(rate))
        append(UInt32(rate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(bytes)
        for sample in samples {
            append(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
