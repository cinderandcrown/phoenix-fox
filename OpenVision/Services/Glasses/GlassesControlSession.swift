// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - GlassesControlSession.swift
// A camera-off device session so buttons, the Neural Band, and the in-lens display
// work without streaming video. The camera session takes over only for an explicit look
// or live video, then this session comes back.
//
// Official DAT 1.0.1. Microphone and speaker stay on Bluetooth HFP (AudioSessionManager),
// which is what Meta's mic/speaker guide documents. This file does not open a second mic.

import Foundation
import MWDATCore
import MWDATInputs
import MWDATSpeech
import MWDATMotion

@MainActor
final class GlassesControlSession {
    static let shared = GlassesControlSession()

    /// Nil when the glasses SDK did not start. See `WearablesSDK`.
    private var wearables: (any WearablesInterface)? { WearablesSDK.interface }
    private var session: DeviceSession?
    private var eventsTask: Task<Void, Never>?
    private var voice: VoiceInvocationsStream?
    // A listener lives only as long as its token. A token that is dropped stops the callback.
    private var voiceTokens: [any AnyListenerToken] = []
    private var speech: Speech?
    private var speechToken: (any AnyListenerToken)?
    private var motion: Motion?
    private var deviceStateToken: (any AnyListenerToken)?
    private var suspendedForCamera = false
    private var deviceId: DeviceIdentifier?

    private init() {}

    func deviceAppeared(_ id: DeviceIdentifier) {
        deviceId = id
        bindDeviceState(id)
        startVoiceInvocations(id)
        guard !suspendedForCamera else { return }
        // Adventurer (DeviceType.metaGlasses) has no display and no Neural Band.
        // An idle session here would compete with the camera session, which is the v1 path.
        // Display cards and band gestures start only when the hardware reports a display.
        guard let device = wearables?.deviceForIdentifier(id),
              device.supportsDisplay() || device.deviceType().supportsDisplay else {
            GlassesLink.shared.record("v1 audio and camera only. No display session.")
            return
        }
        Task { await startControlSession(id) }
    }

    func deviceDisappeared() {
        deviceId = nil
        stop()
    }

    /// Camera streaming needs the device session. Drop the idle session first.
    func suspendForCamera() {
        suspendedForCamera = true
        tearDownSession()
    }

    func resumeAfterCamera() {
        suspendedForCamera = false
        guard let deviceId else { return }
        guard let device = wearables?.deviceForIdentifier(deviceId),
              device.supportsDisplay() || device.deviceType().supportsDisplay else { return }
        Task { await startControlSession(deviceId) }
    }

    func stop() {
        voice?.stop()
        voice = nil
        voiceTokens = []
        deviceStateToken = nil
        tearDownSession()
        GlassesHUD.shared.detach()
    }

    // MARK: - Device state (battery, worn, hinge, thermal)

    private func bindDeviceState(_ id: DeviceIdentifier) {
        deviceStateToken = nil
        guard let device = wearables?.deviceForIdentifier(id) else { return }
        deviceStateToken = device.addDeviceStateListener { state in
            Task { @MainActor in
                GlassesLink.shared.apply(state)
            }
        }
        GlassesLink.shared.noteHardware(
            type: device.deviceType(),
            display: device.supportsDisplay() || device.deviceType().supportsDisplay
        )
    }

    // MARK: - Hey Meta launch (does not replace the wake word)

    private func startVoiceInvocations(_ id: DeviceIdentifier) {
        voice?.stop()
        voiceTokens = []
        guard let wearables else { return }
        do {
            let stream = try VoiceInvocationsStream(wearables: wearables)
            let invocations = stream.invocationsPublisher.listen { invocation in
                guard let launch = invocation as? LaunchApp else { return }
                Task { @MainActor in
                    NotificationCenter.default.post(name: .jarvisVoiceLaunch, object: nil)
                    _ = await launch.responseHandle.sendSuccess(actionOutput: nil)
                }
            }
            let errors = stream.errorPublisher.listen { error in
                let line = error.description
                Task { @MainActor in
                    GlassesLink.shared.record("Voice invocation: \(line)")
                }
            }
            try stream.start(deviceIdentifier: id)
            voice = stream
            voiceTokens = [invocations, errors]
        } catch {
            GlassesLink.shared.record("Voice invocations not started: \(error.localizedDescription)")
        }
    }

    // MARK: - Idle session: inputs, optional speech, optional motion, display

    private func startControlSession(_ id: DeviceIdentifier) async {
        tearDownSession()
        guard let wearables else { return }
        let selector = SpecificDeviceSelector(device: id)
        do {
            let session = try wearables.createSession(deviceSelector: selector)
            let states = session.stateStream()
            try session.start()
            let started = await firstTerminal(states)
            guard started else {
                session.stop()
                GlassesLink.shared.record("Control session did not start")
                return
            }
            self.session = session
            let device = wearables.deviceForIdentifier(id)
            GlassesHUD.shared.attach(to: session, device: device)
            attachInputs(session)
            if SettingsManager.shared.settings.glassesExperimentalSpeech {
                attachSpeech(session)
            }
            if SettingsManager.shared.settings.glassesMotion {
                attachMotion(session)
            }
            GlassesLink.shared.record("Control session up (no camera)")
        } catch {
            GlassesLink.shared.record("Control session failed: \(error.localizedDescription)")
        }
    }

    private func firstTerminal(_ states: AsyncStream<DeviceSessionState>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await state in states {
                    if state == .started { return true }
                    if state == .stopped { return false }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    private func attachInputs(_ session: DeviceSession) {
        do {
            guard let inputs = try session.addInputs() else { return }
            eventsTask = Task {
                for await event in inputs.events {
                    guard let signal = Self.signal(from: event) else { continue }
                    await MainActor.run {
                        GlassesHUD.shared.handle(signal)
                        if let name = Self.notification(for: signal) {
                            NotificationCenter.default.post(name: name, object: nil)
                        }
                    }
                }
            }
        } catch {
            GlassesLink.shared.record("Inputs not attached: \(error.localizedDescription)")
        }
    }

    private func attachSpeech(_ session: DeviceSession) {
        do {
            guard let speech = try session.addSpeech() else { return }
            speechToken = speech.transcriptionPublisher.listen { result in
                guard result.isFinal, !result.text.isEmpty else { return }
                NotificationCenter.default.post(name: .jarvisGlassesTranscript, object: result.text)
            }
            speech.start()
            self.speech = speech
        } catch {
            GlassesLink.shared.record("Glasses speech unavailable: \(error.localizedDescription)")
        }
    }

    private func attachMotion(_ session: DeviceSession) {
        do {
            // 5 Hz is the slowest official rate. Samples are not uploaded.
            guard let motion = try session.addMotion(configuration: MotionConfiguration(samplingRate: .hz5)) else { return }
            motion.start()
            self.motion = motion
        } catch {
            GlassesLink.shared.record("Motion unavailable: \(error.localizedDescription)")
        }
    }

    private func tearDownSession() {
        eventsTask?.cancel()
        eventsTask = nil
        speech?.stop()
        speech = nil
        speechToken = nil
        motion?.stop()
        motion = nil
        GlassesHUD.shared.detach()
        session?.stop()
        session = nil
    }

    /// Nil for an input kind a later SDK adds, which is ignored until `GestureMap` knows it.
    private static func signal(from event: InputEvent) -> GestureSignal? {
        let source: GestureSignal.Source
        switch event.source {
        case .captouch: source = .temple
        case .neuralBand: source = .band
        case .neuralBandDrag: source = .bandDrag
        case .captureButton: source = .captureButton
        case .actionButton: source = .actionButton
        case .unknown: source = .unknown
        }
        let kind: GestureSignal.Kind
        // DAT 1.0.1 InputEvent cases all carry a source and a timestamp.
        switch event {
        case .select(_, _):
            kind = .select
        case .nav(let direction, _, _):
            switch direction {
            case .up: kind = .nav(.up)
            case .down: kind = .nav(.down)
            case .left: kind = .nav(.left)
            case .right: kind = .nav(.right)
            }
        case .back(_, _):
            kind = .back
        case .button(_, _, _):
            kind = .action
        case .capture(let press, _, _):
            switch press {
            case .shortPress: kind = .capture(.short)
            case .hold: kind = .capture(.hold)
            case .doublePress: kind = .capture(.double)
            }
        case .drag(let action, _, _, let dx, _, _, _):
            kind = action == .up ? .dragEnded(dx: dx) : .dragEnded(dx: 0)
        @unknown default:
            return nil
        }
        return GestureSignal(source: source, kind: kind)
    }

    private static func notification(for signal: GestureSignal) -> Notification.Name? {
        switch GestureMap.interpret(signal).gesture {
        case .talkOrConfirm: return .jarvisTalk
        case .look: return .jarvisLook
        case .note: return .jarvisNote
        default: return nil
        }
    }
}

extension Notification.Name {
    static let jarvisVoiceLaunch = Notification.Name("jarvis.voiceLaunch")
    static let jarvisTalk = Notification.Name("jarvis.talk")
    static let jarvisLook = Notification.Name("jarvis.look")
    static let jarvisNote = Notification.Name("jarvis.note")
    static let jarvisGlassesTranscript = Notification.Name("jarvis.glassesTranscript")
}
