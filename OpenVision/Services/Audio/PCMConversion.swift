// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// One pass of an AVAudioConverter over a single PCM buffer.
// The converter pulls input through a @Sendable block that it may call more than
// once, so the buffer is handed over by a locked one-shot feed rather than a
// captured flag.

@preconcurrency import AVFoundation

enum PCMConversion {
    /// Converts `input` into `output` and reports whether anything usable came out.
    ///
    /// Pass `endOfStream: true` for a whole clip, so the converter flushes its tail.
    /// Leave it false for a live tap, where the converter keeps its filter state for
    /// the next buffer.
    @discardableResult
    static func run(
        _ converter: AVAudioConverter,
        from input: AVAudioPCMBuffer,
        into output: AVAudioPCMBuffer,
        endOfStream: Bool = false
    ) -> Bool {
        let feed = SingleBufferFeed(input)
        let drained: AVAudioConverterInputStatus = endOfStream ? .endOfStream : .noDataNow
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            guard let buffer = feed.take() else {
                inputStatus.pointee = drained
                return nil
            }
            inputStatus.pointee = .haveData
            return buffer
        }
        return failure == nil && status != .error && output.frameLength > 0
    }

    /// An output buffer sized for `input` after a sample-rate change, with headroom
    /// for the converter's filter delay.
    static func outputBuffer(for input: AVAudioPCMBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sourceRate = input.format.sampleRate
        guard sourceRate > 0 else { return nil }
        let frames = Double(input.frameLength) * format.sampleRate / sourceRate
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames) + 1024)
    }

    /// Mono float samples at any rate, resampled to `targetRate` with the system's
    /// band-limited converter. Returns the input unchanged when no conversion is needed
    /// or the formats cannot be built.
    static func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate > 0, targetRate > 0, abs(sourceRate - targetRate) >= 1, !samples.isEmpty,
              let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sourceRate, channels: 1, interleaved: false),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(samples.count)),
              let inputChannel = input.floatChannelData?[0]
        else { return samples }

        samples.withUnsafeBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            inputChannel.update(from: base, count: samples.count)
        }
        input.frameLength = AVAudioFrameCount(samples.count)

        guard let output = outputBuffer(for: input, format: target),
              run(converter, from: input, into: output, endOfStream: true),
              let outputChannel = output.floatChannelData?[0]
        else { return samples }
        return Array(UnsafeBufferPointer(start: outputChannel, count: Int(output.frameLength)))
    }
}

/// Hands one buffer to the converter exactly once. The lock is what makes the
/// unchecked conformance true: the buffer is only ever read through `take()`.
private final class SingleBufferFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let next = buffer
        buffer = nil
        return next
    }
}
