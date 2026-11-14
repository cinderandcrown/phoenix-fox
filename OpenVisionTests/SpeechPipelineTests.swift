// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

/// Stands in for Whisper: returns a fixed transcript and records what it was asked.
private actor ScriptedTranscriber: SpeechTranscribing {
    private let reply: String?
    private(set) var calls = 0

    init(reply: String?) {
        self.reply = reply
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> String? {
        calls += 1
        return reply
    }
}

final class SpeechPipelineTests: XCTestCase {

    // MARK: - Choosing a transcript

    @MainActor
    func testWhisperTranscriptWinsWhenPresent() async {
        let engine = ScriptedTranscriber(reply: "ask indy about the gate")
        let transcriber = WhisperTranscriber(engine: engine)
        let heard = await transcriber.resolve(apple: "ask in the about the gate", samples: [0.1], sampleRate: 16_000)
        XCTAssertEqual(heard.transcript, "ask indy about the gate")
        XCTAssertEqual(heard.cleaned, "Ask indy about the gate.")
        let calls = await engine.calls
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testAppleTranscriptIsTheFallback() async {
        let transcriber = WhisperTranscriber(engine: ScriptedTranscriber(reply: nil))
        let heard = await transcriber.resolve(apple: "what time is it", samples: [], sampleRate: 16_000)
        XCTAssertEqual(heard.transcript, "what time is it")
        XCTAssertEqual(heard.cleaned, "What time is it.")
    }

    // MARK: - Engine guards

    func testEngineIgnoresClipsTooShortToBeSpeech() async {
        // No model is loaded for these: the guard returns before the engine touches Whisper.
        let engine = WhisperEngine()
        let click = [Float](repeating: 0.2, count: 1_000)
        let none = await engine.transcribe(samples: click, sampleRate: 16_000)
        XCTAssertNil(none)
        let empty = await engine.transcribe(samples: [], sampleRate: 16_000)
        XCTAssertNil(empty)
        let badRate = await engine.transcribe(samples: click, sampleRate: 0)
        XCTAssertNil(badRate)
    }

    // MARK: - Dictation cleanup

    func testCleanupDropsFillersAndPunctuates() {
        XCTAssertEqual(DictationCleanup.clean("um ask indy uh about the gate"), "Ask indy about the gate.")
        XCTAssertEqual(DictationCleanup.clean("is it open?"), "Is it open?")
    }

    func testCleanupKeepsRealWords() {
        XCTAssertEqual(DictationCleanup.clean("what's it like outside"), "What's it like outside.")
    }

    func testCleanupKeepsTextThatIsOnlyFillers() {
        XCTAssertEqual(DictationCleanup.clean("  um  "), "um")
    }

    // MARK: - Resampling

    func testResampleChangesLengthByTheRateRatio() {
        let second = Self.sine(frequency: 440, rate: 48_000, seconds: 1)
        let resampled = PCMConversion.resample(second, from: 48_000, to: 16_000)
        XCTAssertEqual(Double(resampled.count), 16_000, accuracy: 400)
    }

    func testResampleKeepsTheToneAndItsLevel() {
        let source = Self.sine(frequency: 440, rate: 48_000, seconds: 1)
        let resampled = PCMConversion.resample(source, from: 48_000, to: 16_000)
        // Skip the converter's settling time at each end, then compare level and pitch.
        let middle = Array(resampled.dropFirst(1_600).dropLast(1_600))
        XCTAssertEqual(Self.rms(middle), Self.rms(source), accuracy: 0.05)
        let crossings = zip(middle, middle.dropFirst()).filter { $0 <= 0 && $1 > 0 }.count
        let seconds = Double(middle.count) / 16_000
        XCTAssertEqual(Double(crossings) / seconds, 440, accuracy: 8)
    }

    func testResampleLeavesMatchingRatesAndEmptyInputAlone() {
        let samples: [Float] = [0, 0.5, -0.5, 0.25]
        XCTAssertEqual(PCMConversion.resample(samples, from: 16_000, to: 16_000), samples)
        XCTAssertEqual(PCMConversion.resample([], from: 48_000, to: 16_000), [])
        XCTAssertEqual(PCMConversion.resample(samples, from: 0, to: 16_000), samples)
    }

    // MARK: - Resuming once

    func testFirstResumeWinsAndLaterOnesAreIgnored() async {
        let value: Int = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            once.resume(returning: 1)
            once.resume(returning: 2)
        }
        XCTAssertEqual(value, 1)
    }

    func testResumeOnceUnderContention() async {
        let value: Int = await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.concurrentPerform(iterations: 64) { index in
                once.resume(returning: index)
            }
        }
        XCTAssertTrue((0..<64).contains(value))
    }

    func testThrowingResume() async {
        struct Stopped: Error {}
        do {
            let _: Int = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce(continuation)
                once.resume(throwing: Stopped())
                once.resume(returning: 7)
            }
            XCTFail("Expected the first resume, an error, to win")
        } catch {
            XCTAssertTrue(error is Stopped)
        }
    }

    // MARK: - Helpers

    private static func sine(frequency: Double, rate: Double, seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) * 0.5 }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }
}
