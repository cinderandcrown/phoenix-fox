// OpenVision - TTSService.swift
// Text-to-speech service using AVSpeechSynthesizer

import AVFoundation
import Foundation

/// Text-to-speech service for OpenClaw mode
@MainActor
final class TTSService: NSObject, ObservableObject {
    // MARK: - Singleton

    static let shared = TTSService()

    // MARK: - Published State

    @Published var isSpeaking: Bool = false

    // MARK: - Callbacks

    /// Called when speech starts
    var onSpeechStarted: (() -> Void)?

    /// Called when speech ends
    var onSpeechEnded: (() -> Void)?

    // MARK: - Speech Synthesizer

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Streaming state

    /// Utterances enqueued but not yet finished. `isSpeaking` only drops to false when this
    /// hits 0 AND no more chunks are coming — so it doesn't flap between queued sentences.
    private var pendingUtterances = 0

    /// True while a streamed reply is still being fed sentence-by-sentence. Keeps `isSpeaking`
    /// latched even if the audio queue momentarily drains faster than the LLM produces text.
    private var streamingActive = false

    // MARK: - Voice Selection

    private var selectedVoice: AVSpeechSynthesisVoice? { Self.userVoice }

    /// The Apple voice chosen in Settings, or the most natural installed English voice.
    /// Never prefers a compact/default voice when a Premium or Enhanced voice is installed.
    /// Also used by the cloud voices' Apple fallback, so the choice lives in one place.
    static var userVoice: AVSpeechSynthesisVoice? {
        let preferred = SettingsManager.shared.settings.selectedVoiceIdentifier
        let candidates = voiceCandidates()
        guard let choice = AppleVoiceChoice.pick(from: candidates, preferredIdentifier: preferred) else {
            // Last resort only when the system reports no voices at all.
            return AVSpeechSynthesisVoice(language: "en-US")
        }
        return AVSpeechSynthesisVoice(identifier: choice.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Snapshot of installed voices for ranking and Settings.
    static func voiceCandidates() -> [AppleVoiceCandidate] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            var personal = false
            if #available(iOS 17.0, *) {
                personal = voice.voiceTraits.contains(.isPersonalVoice)
            }
            return AppleVoiceCandidate(
                identifier: voice.identifier,
                name: voice.name,
                qualityRank: AppleVoiceChoice.qualityRank(rawValue: voice.quality.rawValue),
                isPersonal: personal,
                language: voice.language
            )
        }
    }

    /// True when only compact/default English voices are installed.
    static var needsBetterVoicesHint: Bool {
        AppleVoiceChoice.needsBetterVoicesHint(voices: voiceCandidates())
    }

    /// Get all available voices for a language
    static func availableVoices(for languageCode: String = "en") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { v1, v2 in
                // Sort by quality (premium first), then by name
                if v1.quality != v2.quality {
                    return v1.quality.rawValue > v2.quality.rawValue
                }
                return v1.name < v2.name
            }
    }

    /// Get display name for a voice quality
    static func qualityDisplayName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .default: return "Standard (robotic)"
        case .enhanced: return "Enhanced"
        case .premium: return "Premium"
        @unknown default: return "Unknown"
        }
    }

    /// Ask iOS for Personal Voice access when the wearer has one. Safe to call repeatedly.
    static func requestPersonalVoiceAccessIfNeeded() {
        guard #available(iOS 17.0, *) else { return }
        let status = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        guard status == .notDetermined else { return }
        AVSpeechSynthesizer.requestPersonalVoiceAuthorization { _ in }
    }

    /// One-shot notice when the only installed English voices are compact/default.
    /// Never silently settle on a robotic voice without telling the wearer once.
    private static let compactWarnKey = "ov.didWarnCompactVoice"

    static func warnOnceIfOnlyCompactVoices() {
        guard needsBetterVoicesHint else { return }
        guard !UserDefaults.standard.bool(forKey: compactWarnKey) else { return }
        UserDefaults.standard.set(true, forKey: compactWarnKey)
        AccessBanner.shared.show(
            "Using a basic system voice. Download a Premium English voice in iOS Settings → Accessibility → Spoken Content for a more natural sound.",
            urgent: false
        )
    }

    /// Sample line for Settings preview and the onboarding glasses voice check.
    static let glassesSample = "Hi — I'm Jarvis. This is how I sound on your glasses."

    /// Speak the glasses sample on the active audio route (glasses speakers when connected).
    static func playGlassesSample() {
        requestPersonalVoiceAccessIfNeeded()
        let settings = SettingsManager.shared.settings
        if let neural = NeuralSpeech.active(settings) {
            Task { await neural.speak(glassesSample) }
        } else {
            shared.speak(glassesSample)
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak

    /// Speak text (single-shot: replaces anything currently playing).
    func speak(_ text: String) {
        stop()
        enqueue(text)
    }

    /// True when the line last started was one the wearer did not ask for: a Guide mode
    /// callout, a sound alert, a turn on a walk. The voice screen reads this when speech
    /// ends, because such a line is not part of a conversation and must not open one.
    private(set) var announcing = false

    /// Says a line the wearer did not ask for.
    ///
    /// - Parameter urgent: An urgent line interrupts whatever is being said. Any other line
    ///   is dropped if something is already being said.
    func announce(_ text: String, urgent: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if urgent {
            stop()
        } else if isSpeaking || streamingActive {
            return
        }
        announcing = true
        enqueue(trimmed)
    }

    /// Ambient narration (watch loop): speaks only into silence and never preempts — `speak`
    /// stops the synthesizer first, which cut replies off mid-sentence when a watch line landed
    /// during one. Dropped lines are fine; the next scene change describes again.
    func speakAmbient(_ text: String) {
        guard !isSpeaking, !streamingActive else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        announcing = false
        enqueue(trimmed)
    }

    // MARK: - Streaming (sentence-by-sentence)

    /// Begin a streamed reply. Clears the queue and latches `isSpeaking` true so the recognizer
    /// stays paused across the gaps between sentences while the LLM is still generating.
    func beginStreaming() {
        stop()
        streamingActive = true
        isSpeaking = true
        onSpeechStarted?()
    }

    /// Enqueue one sentence without interrupting what's already queued. AVSpeechSynthesizer plays
    /// queued utterances back-to-back, so this pipelines speech behind the LLM as it streams.
    func speakChunk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        announcing = false
        enqueue(trimmed)
    }

    /// Signal that no more sentences are coming. Releases the latch once the queue drains.
    func endStreaming() {
        streamingActive = false
        if pendingUtterances == 0 {
            isSpeaking = false
            onSpeechEnded?()
        }
    }

    /// Build an utterance with the selected voice and hand it to the synthesizer's queue.
    private func enqueue(_ text: String) {
        // Strip markup / emoji / URLs so the ear never hears "asterisk asterisk".
        let spoken = SpokenReply.plain(text)
        guard !spoken.isEmpty else { return }
        Self.warnOnceIfOnlyCompactVoices()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = selectedVoice
        // Natural rate: AVSpeechUtteranceDefaultSpeechRate × Voice speed × accessibility pace.
        // Pitch stays 1.0 — never pitch-shift; a wrong multiplier sounds uncanny/scary.
        let settings = SettingsManager.shared.settings
        let pace = settings.accessibility.pace.rate
        let speed = settings.voiceSpeed
        utterance.rate = min(
            max(AVSpeechUtteranceDefaultSpeechRate * speed * pace, AVSpeechUtteranceMinimumSpeechRate),
            AVSpeechUtteranceMaximumSpeechRate
        )
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Slight pause between sentences for natural prosody.
        utterance.preUtteranceDelay = pendingUtterances == 0 ? 0 : 0.05
        utterance.postUtteranceDelay = 0.12
        pendingUtterances += 1
        synthesizer.speak(utterance)
    }

    /// Stop speaking and clear the queue.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        announcing = false
        streamingActive = false
        pendingUtterances = 0
        isSpeaking = false
    }

    /// Pause speaking
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Continue speaking
    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // The moment audio actually begins — the honest end of the wearer's wait. Marked here,
            // not where the view model hands text over: hand-off-time marking excluded synthesis
            // entirely, which made TTS TTFB structurally zero and perceived latency optimistic.
            // First-wins per turn, and gated inside the collector on the turn having requested
            // TTS, so later sentences and unrelated system utterances can't misattribute.
            MetricsCollector.shared.markFirstAudio()
            AudioSessionManager.shared.logSpeaking()
            if !self.isSpeaking {
                self.isSpeaking = true
                self.onSpeechStarted?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.pendingUtterances = max(0, self.pendingUtterances - 1)
            // Only truly "done" when the queue is empty AND no more sentences are coming.
            if self.pendingUtterances == 0 && !self.streamingActive {
                self.isSpeaking = false
                self.onSpeechEnded?()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.pendingUtterances = max(0, self.pendingUtterances - 1)
            if self.pendingUtterances == 0 {
                self.streamingActive = false
                self.isSpeaking = false
                self.onSpeechEnded?()
            }
        }
    }
}
