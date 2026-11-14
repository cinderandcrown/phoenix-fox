// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - audio captured after the wake word, for on-device Whisper.
// The tap runs on the audio thread. This buffer only copies samples.

import AVFoundation
import Foundation

struct UtteranceClip {
    var samples: [Float]
    var rate: Double
}

final class UtterancePCMBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 48_000
    private var capturing = false

    func begin(rate: Double) {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        self.rate = rate
        capturing = true
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard capturing else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        if rate == 0 { rate = buffer.format.sampleRate }
        if let channel = buffer.floatChannelData?[0] {
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        } else if let channel = buffer.int16ChannelData?[0] {
            samples.append(contentsOf: (0..<count).map { Float(channel[$0]) / 32768 })
        } else {
            return
        }
        if samples.count > 16000 * 30 { samples.removeFirst(samples.count - 16000 * 30) }
    }

    func finish() -> UtteranceClip? {
        lock.lock()
        defer { lock.unlock() }
        capturing = false
        guard samples.count > 1600 else { return nil }
        return UtteranceClip(samples: samples, rate: rate)
    }
}
