// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Listens for sounds a Deaf or hard-of-hearing wearer would want to know about, and tells
// them in ways that do not need hearing: a banner, a vibration, a notification that an
// Apple Watch will tap out, and a card on the lens when the glasses have a display.
//
// The audio is classified on the phone by Apple's SoundAnalysis framework. Nothing is
// recorded and nothing is sent anywhere. It shares the microphone that is already open for
// the wake word, so it hears while Phoenix Fox is listening. In the owner's build it also
// hears the sound that comes with the glasses' camera stream, while the camera is on.

import AVFoundation
import AudioToolbox
import Foundation
import SoundAnalysis
import UIKit
import UserNotifications

/// Hands each buffer from the one open microphone tap to anything else that wants to hear it.
///
/// The speech recognizer owns the tap. Opening a second audio engine for sound alerts would
/// fight it for the microphone, so listeners register here instead.
final class MicFanout: @unchecked Sendable {
    /// The phone's open microphone tap, which is the glasses' hands-free microphone when
    /// they are connected. That microphone is tuned to the wearer's own voice.
    static let shared = MicFanout()

    /// Sound that arrives with the glasses' camera stream. It is the room as it sounds,
    /// not narrowed to the wearer's voice, so it is the better source for sirens,
    /// doorbells, and other people. It flows only while the camera is on with sound.
    static let glasses = MicFanout()

    typealias Listener = @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void

    private let lock = NSLock()
    private var listeners: [String: Listener] = [:]
    /// The listeners as an array, rebuilt only when they change, so the audio thread never
    /// allocates to read them.
    private var current: [Listener] = []

    func add(_ name: String, _ listener: @escaping Listener) {
        lock.lock()
        listeners[name] = listener
        current = Array(listeners.values)
        lock.unlock()
    }

    func remove(_ name: String) {
        lock.lock()
        listeners[name] = nil
        current = Array(listeners.values)
        lock.unlock()
    }

    /// Called from the audio tap. With no listeners this is one lock and a return.
    func send(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        lock.lock()
        let listeners = current
        lastSent = ProcessInfo.processInfo.systemUptime
        lock.unlock()
        for listener in listeners { listener(buffer, time) }
    }

    /// For a source that gives no sample position: counts the samples itself.
    func send(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let position = samplesSent
        samplesSent += Int64(buffer.frameLength)
        lock.unlock()
        send(buffer, at: AVAudioTime(sampleTime: position, atRate: buffer.format.sampleRate))
    }

    /// Starts the sample count again, for a new stream.
    func restart() {
        lock.lock()
        samplesSent = 0
        lock.unlock()
    }

    var hasListeners: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !listeners.isEmpty
    }

    /// Whether a buffer came through in the last half second.
    var isFlowing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return ProcessInfo.processInfo.systemUptime - lastSent < 0.5
    }

    private var samplesSent: Int64 = 0
    private var lastSent: TimeInterval = -1_000
}

@MainActor
final class SoundAlertService: ObservableObject {
    static let shared = SoundAlertService()

    @Published private(set) var isOn = false
    /// The sounds being listened for.
    private(set) var kinds: Set<SoundKind> = []
    /// The alerts raised this session, newest first, for the captions screen.
    @Published private(set) var recent: [SoundAlert] = []

    private var listener: SoundListener?

    private init() {}

    /// Starts listening. Returns the line to say.
    func start(kinds: Set<SoundKind>) -> String {
        stop()
        let listener = SoundListener(enabled: kinds) { alert in
            Task { @MainActor in SoundAlertService.shared.raise(alert) }
        }
        self.listener = listener
        self.kinds = kinds
        // One classifier, two possible sources. While the glasses' camera stream carries
        // the sound of the room, that is used and the hands-free microphone is passed
        // over: it is tuned to the wearer's voice and turns a siren down.
        let room = MicFanout.glasses
        MicFanout.shared.add("sound-alerts") { buffer, time in
            if !room.isFlowing { listener.hear(buffer, at: time, from: .phone) }
        }
        room.add("sound-alerts") { buffer, time in listener.hear(buffer, at: time, from: .glasses) }
        // iOS mutes vibration while the microphone is recording unless asked not to.
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        isOn = true
        return "Sound alerts are on. I'll show an alert and vibrate the phone for sirens, alarms, the doorbell, knocking, and the other sounds you chose. It works while I'm listening, and the sound never leaves this phone."
    }

    func stop() {
        MicFanout.shared.remove("sound-alerts")
        MicFanout.glasses.remove("sound-alerts")
        listener = nil
        isOn = false
    }

    /// Shows one alert every way that does not depend on hearing.
    func raise(_ alert: SoundAlert) {
        recent.insert(alert, at: 0)
        if recent.count > 30 { recent.removeLast() }
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AccessBanner.shared.show(alert.kind.message, urgent: alert.kind.urgent)
        notify(alert.kind.message)
        let speak = SettingsManager.shared.settings.accessibility.speakSoundAlerts
        CompanionSurface.present(bot: "Sound alert", text: alert.kind.message, kind: .alert) { line in
            if speak { TTSService.shared.announce(line, urgent: alert.kind.urgent) }
        }
    }

    /// An alert for the wearer's name, raised by live captions.
    func raiseNameCalled(_ name: String) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let message = "Someone said \(name.capitalized)"
        AccessBanner.shared.show(message, urgent: false)
        notify(message)
        CompanionSurface.present(bot: "Sound alert", text: message, kind: .alert) { _ in }
    }

    private func notify(_ message: String) {
        Task {
            let content = UNMutableNotificationContent()
            content.title = "Phoenix Fox heard"
            content.body = message
            content.sound = .default
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "sound-alert-\(UUID().uuidString)", content: content, trigger: nil)
            )
        }
    }
}

/// The part that runs off the main thread: feeds audio to the classifier and applies the
/// alert policy to what comes back.
private final class SoundListener: NSObject, SNResultsObserving, @unchecked Sendable {
    private let queue = DispatchQueue(label: "phoenix.sound-alerts")
    private let onAlert: @Sendable (SoundAlert) -> Void
    // Everything below is touched only on `queue`.
    private var analyzer: SNAudioStreamAnalyzer?
    private var format: AVAudioFormat?
    private var source: Source?

    enum Source: Sendable { case phone, glasses }
    private var policy: SoundAlertPolicy

    init(enabled: Set<SoundKind>, onAlert: @escaping @Sendable (SoundAlert) -> Void) {
        policy = SoundAlertPolicy(enabled: enabled)
        self.onAlert = onAlert
        super.init()
    }

    func hear(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime, from source: Source) {
        // The tap hands over a buffer it does not touch again, so it is safe to carry it
        // to the analysis queue.
        let audio = Carried(value: buffer)
        let position = time.sampleTime
        queue.async { [self] in
            let buffer = audio.value
            // The route can change mid-session, phone microphone to glasses, and with it
            // the format. The analyzer is rebuilt for the new one.
            // A change of source starts the sample positions again, even when the two
            // happen to share a format.
            if analyzer == nil || format != buffer.format || self.source != source {
                analyzer = Self.makeAnalyzer(format: buffer.format, observer: self)
                format = buffer.format
                self.source = source
            }
            analyzer?.analyze(buffer, atAudioFramePosition: position)
        }
    }

    private struct Carried<Value>: @unchecked Sendable {
        let value: Value
    }

    private static func makeAnalyzer(format: AVAudioFormat, observer: SNResultsObserving) -> SNAudioStreamAnalyzer? {
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        // Shorter windows than the default, so an alarm is reported in about two seconds.
        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        request.overlapFactor = 0.5
        let analyzer = SNAudioStreamAnalyzer(format: format)
        guard (try? analyzer.add(request, withObserver: observer)) != nil else { return nil }
        return analyzer
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let scores = result.classifications.map { (label: $0.identifier, confidence: $0.confidence) }
        queue.async { [self] in
            for alert in policy.observe(scores, at: Date()) { onAlert(alert) }
        }
    }
}

/// A large on-screen alert, shown over whatever the app is displaying.
@MainActor
final class AccessBanner: ObservableObject {
    static let shared = AccessBanner()

    @Published private(set) var message: String?
    @Published private(set) var urgent = false
    private var hide: Task<Void, Never>?

    private init() {}

    func show(_ message: String, urgent: Bool) {
        self.message = message
        self.urgent = urgent
        // A wearer who is deaf-blind may read the phone through VoiceOver and a braille display.
        UIAccessibility.post(notification: .announcement, argument: message)
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(urgent ? 12 : 6))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func dismiss() {
        hide?.cancel()
        message = nil
    }
}
