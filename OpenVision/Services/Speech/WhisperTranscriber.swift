// Phoenix Fox - on-device Whisper, with the Apple transcript as the fallback.
// Model weights download on first use and are not stored in the repo.

import AVFoundation
import Foundation
import WhisperKit

struct HeardTurn {
    var transcript: String
    var cleaned: String
}

@MainActor
final class WhisperTranscriber {
    static let shared = WhisperTranscriber()

    private var pipe: WhisperKit?
    private var loading: Task<WhisperKit?, Never>?

    private init() {
        loading = Task { await self.load() }
    }

    func resolve(apple: String, samples: [Float], sampleRate: Double) async -> HeardTurn {
        let whisper = await transcribe(samples: samples, sampleRate: sampleRate)
        let raw = (whisper?.isEmpty == false) ? whisper! : apple
        return HeardTurn(transcript: raw, cleaned: DictationCleanup.clean(raw))
    }

    private func transcribe(samples: [Float], sampleRate: Double) async -> String? {
        guard samples.count > 1600 else { return nil }
        let kit = pipe ?? await loading?.value
        guard let kit else { return nil }
        let audio = Self.resample(samples, from: sampleRate, to: 16_000)
        let results = await kit.transcribe(audioArrays: [audio])
        let text = (results.first ?? nil)?.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func load() async -> WhisperKit? {
        let config = WhisperKitConfig(
            model: "base",
            verbose: false,
            prewarm: true,
            load: true,
            download: true
        )
        do {
            let kit = try await WhisperKit(config)
            pipe = kit
            return kit
        } catch {
            GlassesLink.shared.record("Whisper unavailable, using Apple speech: \(error.localizedDescription)")
            return nil
        }
    }

    private static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from > 0, abs(from - to) > 1 else { return samples }
        let ratio = to / from
        let count = Int(Double(samples.count) * ratio)
        guard count > 0 else { return samples }
        var output = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let source = Double(index) / ratio
            let left = Int(source)
            let right = min(left + 1, samples.count - 1)
            let fraction = Float(source - Double(left))
            output[index] = samples[left] * (1 - fraction) + samples[right] * fraction
        }
        return output
    }
}

enum DictationCleanup {
    private static let fillers: Set<String> = ["um", "uh", "er", "ah", "like", "you know", "i mean"]

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
