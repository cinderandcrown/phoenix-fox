// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Live captions of the conversation around the wearer.
//
// The words come from the speech recognizer that is already listening for the wake word,
// so captions add no second microphone and no second recognizer. While captions are on,
// that recognizer is asked to work on the phone only, so other people's speech is not sent
// to a server. Lines are shown on the iPhone, and on the lens when the glasses have a
// display. Nothing is kept after captions stop unless the wearer asks to save it.

import Foundation

struct SavedTranscript: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var savedAt: Date
    var text: String
}

@MainActor
final class LiveCaptions: ObservableObject {
    static let shared = LiveCaptions()

    @Published private(set) var isOn = false
    @Published private(set) var book = CaptionBook()
    @Published private(set) var saved: [SavedTranscript]

    /// Set by the voice screen: asks the recognizer to stay on the phone, or lets it go
    /// back to its normal mode. Returns whether recognition is now on the phone only.
    var setOnDeviceRecognition: ((Bool) -> Bool)?

    private var ticker: Task<Void, Never>?
    private var names = NameCallDetector(names: [])
    private var lastLens = Date.distantPast
    private static let file = "transcripts"

    private init() {
        saved = AccessStore.load([SavedTranscript].self, from: Self.file) ?? []
    }

    func start() -> String {
        guard !isOn else { return "Captions are already on." }
        guard VoiceCommandService.shared.isListening else {
            return "Captions use the microphone. Start listening on the main screen first."
        }
        isOn = true
        names = NameCallDetector(names: SettingsManager.shared.settings.accessibility.names)
        let onPhone = setOnDeviceRecognition?(true) ?? false
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                self?.tick()
            }
        }
        let lens = GlassesLink.shared.displayCapable ? " and on the lens" : ""
        // Older phones and some languages have no on-device recognizer. Then the audio goes
        // to Apple to be recognized, as it does for the wake word, and the wearer is told.
        let place = onPhone
            ? "The words are worked out on this phone"
            : "This phone can't recognize speech by itself, so Apple's speech service works out the words"
        return "Captions are on. What people say appears on your phone\(lens). \(place), and they are not kept unless you say save this conversation."
    }

    func stop() -> String {
        guard isOn else { return "Captions are already off." }
        isOn = false
        ticker?.cancel()
        ticker = nil
        _ = setOnDeviceRecognition?(false)
        book.commit(at: Date())
        let kept = SettingsManager.shared.settings.accessibility.keepTranscripts
        if !kept { book.clear() }
        CompanionRuntime.shared.caption = ""
        return kept
            ? "Captions are off. The lines are still on the captions screen until you clear them."
            : "Captions are off, and the lines are cleared."
    }

    /// The recognizer's text for its current session, while it waits for the wake word.
    func heard(_ sessionText: String) {
        guard isOn else { return }
        let now = Date()
        // The microphone also hears Phoenix Fox talking. Those words are passed over.
        if TTSService.shared.isSpeaking || NeuralSpeech.isAnySpeaking {
            book.skip(sessionText, at: now)
            return
        }
        book.update(sessionText, at: now)
        if let name = names.heard(book.live, at: now) {
            SoundAlertService.shared.raiseNameCalled(name)
        }
        show(now)
    }

    /// The recognizer started a new session, so its text begins again from nothing.
    func recognizerRestarted() {
        guard isOn else { return }
        book.sessionEnded(at: Date())
    }

    private func tick() {
        let before = book.lines.count
        book.tick(at: Date())
        if book.lines.count != before { show(Date()) }
    }

    /// Puts the newest lines on the voice screen, and on the lens at most twice a second.
    private func show(_ now: Date) {
        CompanionRuntime.shared.caption = book.tail(lines: 3, charactersPerLine: 44).joined(separator: "\n")
        guard GlassesLink.shared.displayCapable, now.timeIntervalSince(lastLens) > 0.5 else { return }
        lastLens = now
        GlassesHUD.shared.presentCaption(book.tail(lines: 2, charactersPerLine: 32))
    }

    /// The last half minute, for "what did they say?".
    func recentSpoken() -> String {
        guard isOn || !book.lines.isEmpty else { return "Captions are off. Say start captions and I'll keep up with the conversation." }
        let lines = book.recent(seconds: 30, now: Date())
        return lines.isEmpty ? "Nobody has said anything I could catch in the last half minute." : "They said: " + lines.joined(separator: ". ")
    }

    /// Keeps the current lines as a transcript on this phone.
    func save() -> String {
        book.commit(at: Date())
        let text = book.transcript()
        guard !text.isEmpty else { return "There is nothing to save yet. Start captions first." }
        saved.insert(SavedTranscript(id: UUID(), savedAt: Date(), text: text), at: 0)
        guard AccessStore.save(saved, to: Self.file) else {
            saved.removeFirst()
            return "I couldn't save the transcript on this phone."
        }
        return "Saved. It's on the captions screen, on this phone only. Ask the people you were talking with before you share it."
    }

    func clear() -> String {
        book.clear()
        CompanionRuntime.shared.caption = ""
        return "The captions are cleared."
    }

    func delete(_ transcript: SavedTranscript) {
        saved.removeAll { $0.id == transcript.id }
        if saved.isEmpty { AccessStore.remove(Self.file) } else { AccessStore.save(saved, to: Self.file) }
    }
}
