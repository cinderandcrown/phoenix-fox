// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - on-device Whisper, with the Apple transcript as the fallback.
// Model weights download on first use and are not stored in the repo.
// Audio never leaves the phone on this path.

import Foundation
import WhisperKit

/// What the wearer said, as heard and as tidied for sending.
struct HeardTurn: Sendable, Equatable {
    var transcript: String
    var cleaned: String
}

/// Turns one utterance of mono audio into text. Returns nil when it has nothing to offer,
/// which tells the caller to keep the transcript it already has.
protocol SpeechTranscribing: Sendable {
    func transcribe(samples: [Float], sampleRate: Double) async -> String?
}

/// Re-hears the clip captured after the wake word and picks the better transcript.
@MainActor
final class WhisperTranscriber {
    static let shared = WhisperTranscriber(engine: WhisperEngine(onLoadFailure: { reason in
        Task { @MainActor in
            GlassesLink.shared.record("Whisper unavailable, using Apple speech: \(reason)")
        }
    }))

    private let engine: any SpeechTranscribing

    init(engine: any SpeechTranscribing) {
        self.engine = engine
    }

    /// Whisper's transcript when it has one, otherwise the live Apple transcript.
    func resolve(apple: String, samples: [Float], sampleRate: Double) async -> HeardTurn {
        let whisper = await engine.transcribe(samples: samples, sampleRate: sampleRate)
        let raw = whisper ?? apple
        return HeardTurn(transcript: raw, cleaned: DictationCleanup.clean(raw))
    }
}

/// Owns the Whisper model and runs one transcription at a time.
///
/// The model loads on the first utterance, not at launch, so a wearer who never uses the
/// relay backend never pays for the download or the memory. A failed load is retried after
/// a pause rather than on every utterance.
actor WhisperEngine: SpeechTranscribing {
    /// Whisper's native sample rate.
    static let sampleRate: Double = 16_000
    /// Clips shorter than this are a click or a breath, not speech.
    static let minimumDuration: Double = 0.3

    private let model: String
    private let retryDelay: Duration
    private let onLoadFailure: @Sendable (String) -> Void

    private var loading: Task<WhisperSession?, Never>?
    private var session: WhisperSession?
    private var retryAfter: ContinuousClock.Instant?
    private var queue: Task<String?, Never>?

    init(
        model: String = "base",
        retryDelay: Duration = .seconds(60),
        onLoadFailure: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.model = model
        self.retryDelay = retryDelay
        self.onLoadFailure = onLoadFailure
    }

    func transcribe(samples: [Float], sampleRate: Double) async -> String? {
        guard sampleRate > 0, Double(samples.count) / sampleRate >= Self.minimumDuration else { return nil }
        // The pipeline is not safe to run twice at once, and an actor lets other calls in at
        // every await, so each request waits for the one before it.
        let previous = queue
        let request = Task { () -> String? in
            _ = await previous?.value
            guard let session = await self.readySession() else { return nil }
            let audio = PCMConversion.resample(samples, from: sampleRate, to: Self.sampleRate)
            return await session.text(for: audio)
        }
        queue = request
        return await request.value
    }

    /// Frees the model's memory. The next utterance loads it again.
    func unload() {
        loading?.cancel()
        loading = nil
        session = nil
    }

    private func readySession() async -> WhisperSession? {
        if let session { return session }
        if let retryAfter, ContinuousClock.now < retryAfter { return nil }
        if loading == nil {
            let model = model
            let report = onLoadFailure
            loading = Task.detached(priority: .userInitiated) {
                await WhisperSession.load(model: model, onFailure: report)
            }
        }
        let loaded = await loading?.value
        loading = nil
        session = loaded
        retryAfter = loaded == nil ? ContinuousClock.now + retryDelay : nil
        return loaded
    }
}

/// The loaded WhisperKit pipeline.
///
/// `WhisperKit` is not `Sendable`. This box is, because `WhisperEngine` is its only user and
/// runs one transcription at a time, so the pipeline is never touched from two tasks at once.
private final class WhisperSession: @unchecked Sendable {
    private let kit: WhisperKit

    private init(kit: WhisperKit) {
        self.kit = kit
    }

    static func load(model: String, onFailure: @Sendable (String) -> Void) async -> WhisperSession? {
        let config = WhisperKitConfig(model: model, verbose: false, prewarm: true, load: true, download: true)
        do {
            return WhisperSession(kit: try await WhisperKit(config))
        } catch {
            onFailure(error.localizedDescription)
            return nil
        }
    }

    func text(for audio: [Float]) async -> String? {
        // Timestamps and special tokens are for subtitles. A spoken command needs the words only.
        let options = DecodingOptions(skipSpecialTokens: true, withoutTimestamps: true)
        guard let results = try? await kit.transcribe(audioArray: audio, decodeOptions: options) else { return nil }
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Tidies a dictated sentence before it is sent: drops hesitation sounds, capitalises the
/// first letter, and closes the sentence. Real words are never removed, so "what's it like"
/// keeps its "like".
enum DictationCleanup {
    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm"]

    static func clean(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        words.removeAll { fillers.contains($0.lowercased().trimmingCharacters(in: .punctuationCharacters)) }
        var sentence = words.joined(separator: " ")
        sentence = sentence.replacingOccurrences(of: " ,", with: ",")
        sentence = sentence.replacingOccurrences(of: " .", with: ".")
        sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let first = sentence.first, first.isLetter, first.isLowercase {
            sentence.replaceSubrange(sentence.startIndex...sentence.startIndex, with: String(first).uppercased())
        }
        if let last = sentence.last, !".!?".contains(last) { sentence += "." }
        return sentence
    }
}
