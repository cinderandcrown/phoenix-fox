// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - GlassesControlSession.swift
// The session with the glasses that is not about the camera: the touchpad and buttons,
// nods and shakes of the head, speech the glasses turn into text, and the lens of
// glasses that have one.
//
// Official DAT 1.0.1. Microphone and speaker stay on Bluetooth HFP (AudioSessionManager),
// which is what Meta's mic/speaker guide documents. This file does not open a second mic.
//
// When the session is open
// ------------------------
// While any session is open, the glasses keep two touchpad gestures for themselves: a
// single tap pauses the session and a long press ends it. A session that stayed open all
// day would take those gestures away from the wearer all day. So on glasses without a
// display the session is open only when something needs it:
//
// - while Jarvis is busy with the wearer, and for a short time after, for the controls
//   and head gestures;
// - while the camera is on, which borrows this session instead of opening a second one;
// - while the phone's microphone is not listening, when speech on the glasses is on.
//
// Glasses with a display keep the session for as long as they are worn, because cards on
// the lens need it.
//
// The wearer has the last word. A session that the glasses end, with a long press or by
// folding them, is not opened again until the wearer next talks to Jarvis or puts the
// glasses back on.

import Foundation
import MWDATCore
import MWDATInputs
import MWDATSpeech
import MWDATMotion

@MainActor
final class GlassesControlSession {
    static let shared = GlassesControlSession()

    /// How long the session stays after Jarvis has finished, so a press or a nod that
    /// follows the answer still arrives.
    private static let linger: Duration = .seconds(20)
    /// The phone's recognizer restarts in a blink between phrases. It has to be down for
    /// this long before the glasses' ear takes over.
    private static let deafFor: Duration = .seconds(4)
    /// How many times one session's controls are attached again after they report an error.
    private static let inputRepairs = 3

    /// Nil when the glasses SDK did not start. See `WearablesSDK`.
    private var wearables: (any WearablesInterface)? { WearablesSDK.interface }
    private var capabilities: GlassesCapabilitySettings { SettingsManager.shared.glassesCapabilities }

    private var deviceId: DeviceIdentifier?
    private var hasDisplay = false
    private var deviceStateToken: (any AnyListenerToken)?

    // "Hey Meta, open Phoenix Fox"
    private var voice: VoiceInvocationsStream?
    // A listener lives only as long as its token. A token that is dropped stops the callback.
    private var voiceTokens: [any AnyListenerToken] = []

    // The session
    private var session: DeviceSession?
    private var opening: Task<Void, Never>?
    private var sessionWatch: Task<Void, Never>?
    private var paused = false
    /// The camera is using this session.
    private var lentToCamera = false
    /// The camera has a session of its own, and there can be only one.
    private var suspendedForCamera = false
    /// The glasses ended the last session. See the note at the top of the file.
    private var stoodDown = false

    // Why a session is wanted
    private var engaged = false
    private var lingering: Task<Void, Never>?
    private var phoneListening = true
    private var phoneWentDeaf: Task<Void, Never>?

    // Touchpad and buttons
    private var inputs: Inputs?
    private var inputSources: Set<InputSource> = []
    private var inputEvents: Task<Void, Never>?
    private var inputErrors: (any AnyListenerToken)?
    private var inputRepairsLeft = GlassesControlSession.inputRepairs
    private var presses = CapturePressBuffer()
    private var pressRelease: Task<Void, Never>?
    private var dragTravel: Float = 0

    // Head gestures (DAT Motion / IMU — beta, no runtime permission)
    private var motion: Motion?
    private var motionSamples: Task<Void, Never>?
    private var motionTokens: [any AnyListenerToken] = []

    // Speech on the glasses
    private var speech: Speech?
    private var speechTokens: [any AnyListenerToken] = []
    private var speechPacer = RestartPacer()
    private var speechRestart: Task<Void, Never>?
    private var speechRefused = false
    private var checkingSpeechPermission = false

    private init() {}

    // MARK: - The glasses come and go

    func deviceAppeared(_ id: DeviceIdentifier) {
        deviceId = id
        stoodDown = false
        speechRefused = false
        bindDeviceState(id)
        startVoiceInvocations(id)
        reconcile()
    }

    func deviceDisappeared() {
        deviceId = nil
        hasDisplay = false
        voice?.stop()
        voice = nil
        voiceTokens = []
        deviceStateToken = nil
        lentToCamera = false
        close()
    }

    /// Current firmware stops sending presses after the glasses are taken off and put
    /// back on. The controls are attached again, and a session that was let go while the
    /// glasses were off may come back.
    func glassesPutOn() {
        stoodDown = false
        if let session, inputs != nil {
            detachInputs(from: session)
        }
        reconcile()
    }

    /// Nothing is asked of glasses that are not being worn, unless the camera is on.
    func glassesTakenOff() {
        reconcile()
    }

    /// Hot glasses shed the optional work first, and everything from critical on.
    func heatChanged(to heat: GlassesHeat) {
        reconcile()
    }

    func settingsChanged() {
        speechRefused = false
        reconcile()
    }

    // MARK: - Why a session is wanted

    /// Whether Jarvis is busy with the wearer: from the wake word until the answer ends.
    func attention(_ has: Bool) {
        guard has != engaged else { return }
        engaged = has
        if has {
            stoodDown = false
            lingering?.cancel()
            lingering = nil
        } else {
            startLingering()
        }
        reconcile()
    }

    /// Whether the phone's own recognizer is listening for the wake word.
    func phoneIsListening(_ listening: Bool) {
        phoneWentDeaf?.cancel()
        phoneWentDeaf = nil
        if listening {
            guard !phoneListening else { return }
            phoneListening = true
            reconcile()
        } else if phoneListening {
            phoneWentDeaf = Task {
                try? await Task.sleep(for: Self.deafFor)
                guard !Task.isCancelled else { return }
                self.phoneWentDeaf = nil
                self.phoneListening = false
                self.reconcile()
            }
        }
    }

    private func startLingering() {
        lingering?.cancel()
        lingering = Task {
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled else { return }
            self.lingering = nil
            self.reconcile()
        }
    }

    private var busyWithWearer: Bool { engaged || lingering != nil }

    private var wantsSpeech: Bool {
        capabilities.onGlassesSpeech && !phoneListening && !speechRefused
            && GlassesLink.shared.heat < .severe
    }

    private var wantsHeadGestures: Bool {
        capabilities.headGestures && busyWithWearer && GlassesLink.shared.heat < .severe
    }

    private var wantsSession: Bool {
        guard deviceId != nil, !suspendedForCamera else { return false }
        if lentToCamera { return true }
        guard !stoodDown, !GlassesLink.shared.takenOff, GlassesLink.shared.heat < .critical else { return false }
        if hasDisplay { return true }
        if wantsSpeech { return true }
        return capabilities.usesSessionWhileEngaged && busyWithWearer
    }

    /// Makes the session, and what is attached to it, match what is wanted now.
    private func reconcile() {
        if wantsSession {
            if let session {
                attachWhatIsWanted(to: session)
            } else if opening == nil {
                open()
            }
        } else if session != nil || opening != nil {
            close()
        }
    }

    // MARK: - The camera shares the session

    /// The session for the camera to use, when one is open and running. The camera then
    /// starts without the wait for a second session, and the controls keep working while
    /// it is on.
    func lendForCamera() async -> DeviceSession? {
        // A session that is on its way up is worth a short wait: the camera would
        // otherwise have to close it and start the same thing again.
        var waited = 0
        while opening != nil, waited < 30 {
            try? await Task.sleep(for: .milliseconds(200))
            waited += 1
        }
        guard let session, !paused, !suspendedForCamera, session.state == .started else { return nil }
        lentToCamera = true
        return session
    }

    /// The camera has finished with the session it borrowed.
    func cameraReturned() {
        lentToCamera = false
        if !engaged { startLingering() }
        reconcile()
    }

    /// The camera is opening a session of its own. This one is closed first and stays
    /// closed until `resumeAfterCamera()`, because the glasses hold one session at a time.
    func suspendForCamera() async {
        suspendedForCamera = true
        lentToCamera = false
        let pending = opening
        let closing = session
        let states = closing?.stateStream()
        close()
        // An opening that was cancelled stops its own session before it returns.
        await pending?.value
        guard let closing, let states, closing.state != .stopped else { return }
        _ = await Self.first(of: [.stopped], in: states, within: .milliseconds(1500))
    }

    func resumeAfterCamera() {
        suspendedForCamera = false
        reconcile()
    }

    // MARK: - Device state (battery, worn, hinge, thermal)

    private func bindDeviceState(_ id: DeviceIdentifier) {
        deviceStateToken = nil
        guard let device = wearables?.deviceForIdentifier(id) else { return }
        hasDisplay = device.supportsDisplay() || device.deviceType().supportsDisplay
        deviceStateToken = device.addDeviceStateListener { state in
            Task { @MainActor in
                GlassesLink.shared.apply(state)
            }
        }
        GlassesLink.shared.noteHardware(type: device.deviceType(), display: hasDisplay)
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

    // MARK: - Opening and closing

    private func open() {
        guard let wearables, let id = deviceId else { return }
        opening = Task {
            let started = await Self.start(on: id, wearables: wearables)
            self.opening = nil
            guard let started else {
                // An opening that was called off, and is wanted again by now, starts over.
                // One that failed waits for the next reason to try.
                if Task.isCancelled { self.reconcile() }
                return
            }
            // What is wanted can change during the seconds a session takes to start.
            guard self.wantsSession, self.deviceId == id else {
                started.stop()
                return
            }
            self.session = started
            self.paused = false
            self.inputRepairsLeft = Self.inputRepairs
            self.watch(started)
            if self.hasDisplay {
                GlassesHUD.shared.attach(to: started, device: wearables.deviceForIdentifier(id))
            }
            self.attachWhatIsWanted(to: started)
            GlassesLink.shared.record("Control session open, camera off.")
        }
    }

    /// Starts a session and waits until it runs. Nil when it did not.
    private static func start(on id: DeviceIdentifier, wearables: any WearablesInterface) async -> DeviceSession? {
        do {
            let session = try wearables.createSession(deviceSelector: SpecificDeviceSelector(device: id))
            // Taken before start() so the change to started cannot be missed.
            let states = session.stateStream()
            try session.start()
            guard await first(of: [.started, .stopped], in: states, within: .seconds(12)) == .started else {
                session.stop()
                if !Task.isCancelled { GlassesLink.shared.record("Control session did not start.") }
                return nil
            }
            return session
        } catch {
            GlassesLink.shared.record("Control session failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The first of the wanted states the session reaches, or nil when the time runs out.
    private static func first(
        of wanted: [DeviceSessionState],
        in states: AsyncStream<DeviceSessionState>,
        within limit: Duration
    ) async -> DeviceSessionState? {
        await withTaskGroup(of: DeviceSessionState?.self) { group in
            group.addTask {
                for await state in states where wanted.contains(state) { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func watch(_ session: DeviceSession) {
        sessionWatch?.cancel()
        let states = session.stateStream()
        sessionWatch = Task {
            for await state in states {
                guard !Task.isCancelled else { return }
                await self.sessionChanged(to: state, on: session)
            }
        }
    }

    private func sessionChanged(to state: DeviceSessionState, on changed: DeviceSession) async {
        guard let session, session === changed else { return }
        let lent = lentToCamera
        switch state {
        case .paused:
            // The wearer tapped the touchpad. Nothing arrives while paused, and the
            // session resumes by itself on the next tap. Restarting it would fight them.
            if !paused {
                paused = true
                speechRestart?.cancel()
                speechRestart = nil
                if !lent { GlassesLink.shared.record("Control session paused from the glasses.") }
            }
        case .started:
            if paused {
                paused = false
                if !lent { GlassesLink.shared.record("Control session resumed.") }
                attachWhatIsWanted(to: session)
            }
        case .stopped:
            // A long press, folded glasses, or another app took the glasses.
            stoodDown = !suspendedForCamera
            letGo(stopping: false)
            if !lent { GlassesLink.shared.record("The glasses ended the control session.") }
        case .idle, .starting, .stopping:
            break
        }
        // The camera follows the same session and hears about it from here.
        if lent {
            await GlassesManager.shared.sessionChanged(to: state, session: changed)
        }
    }

    private func close() {
        opening?.cancel()
        letGo(stopping: true)
    }

    /// Forgets the session and everything attached to it.
    private func letGo(stopping: Bool) {
        sessionWatch?.cancel()
        sessionWatch = nil
        forgetInputs()
        forgetMotion()
        forgetSpeech()
        GlassesHUD.shared.detach()
        if stopping { session?.stop() }
        session = nil
        paused = false
    }

    // MARK: - What is attached

    private func attachWhatIsWanted(to session: DeviceSession) {
        guard !paused, session.state == .started else { return }

        let sources = wantedInputSources
        if sources != inputSources || (inputs == nil && !sources.isEmpty) {
            detachInputs(from: session)
            if !sources.isEmpty { attachInputs(to: session, sources: sources) }
        }

        if wantsHeadGestures {
            if motion == nil { attachMotion(to: session) }
        } else if motion != nil {
            detachMotion(from: session)
        }

        if wantsSpeech {
            if speech == nil { attachSpeech(to: session) }
        } else if speech != nil {
            detachSpeech(from: session)
        }
    }

    // MARK: - Touchpad and buttons

    /// The controls to ask the glasses for. Only what is switched on is asked for, so the
    /// glasses keep handling the rest themselves: with the capture button left out, a
    /// press still takes a photo with Meta's own camera.
    private var wantedInputSources: Set<InputSource> {
        let capabilities = self.capabilities
        var sources: Set<InputSource> = []
        if capabilities.controls || hasDisplay {
            sources.formUnion([.captouch, .actionButton])
            if hasDisplay { sources.formUnion([.neuralBand, .neuralBandDrag]) }
        }
        if capabilities.captureButton { sources.insert(.captureButton) }
        return sources
    }

    private func attachInputs(to session: DeviceSession, sources: Set<InputSource>) {
        // An empty set would mean every control, which is the opposite of none.
        guard !sources.isEmpty else { return }
        do {
            let configuration = InputsConfiguration(sources: sources, consumeBack: hasDisplay)
            guard let inputs = try session.addInputs(configuration: configuration) else { return }
            self.inputs = inputs
            inputSources = sources
            let events = inputs.events
            inputEvents = Task {
                for await event in events {
                    guard !Task.isCancelled else { return }
                    self.take(event)
                }
            }
            inputErrors = inputs.errorPublisher.listen { error in
                let reason = error.description
                Task { @MainActor in
                    self.inputsFailed(inputs, reason: reason)
                }
            }
        } catch {
            GlassesLink.shared.record("Controls not attached: \(error.localizedDescription)")
        }
    }

    /// After an error the controls deliver nothing more but stay attached. They are
    /// removed and added again, a few times at most for one session.
    private func inputsFailed(_ failed: Inputs, reason: String) {
        guard let session, let inputs, inputs === failed else { return }
        GlassesLink.shared.record("Controls stopped: \(reason)")
        detachInputs(from: session)
        guard inputRepairsLeft > 0 else { return }
        inputRepairsLeft -= 1
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.reconcile()
        }
    }

    private func detachInputs(from session: DeviceSession) {
        guard inputs != nil else { return }
        forgetInputs()
        do {
            try session.removeInputs()
        } catch {
            GlassesLink.shared.record("Controls not removed: \(error.localizedDescription)")
        }
    }

    private func forgetInputs() {
        inputEvents?.cancel()
        inputEvents = nil
        inputErrors = nil
        inputs = nil
        inputSources = []
        pressRelease?.cancel()
        pressRelease = nil
        presses = CapturePressBuffer()
        dragTravel = 0
    }

    private func take(_ event: InputEvent) {
        let source = Self.source(of: event.source)
        switch event {
        case .select:
            act(on: GestureSignal(source: source, kind: .select))
        case .back:
            act(on: GestureSignal(source: source, kind: .back))
        case .button:
            act(on: GestureSignal(source: source, kind: .action))
        case .nav(let direction, _, _):
            let nav: GestureSignal.Nav
            switch direction {
            case .up: nav = .up
            case .down: nav = .down
            case .left: nav = .left
            case .right: nav = .right
            }
            act(on: GestureSignal(source: source, kind: .nav(nav)))
        case .capture(let press, _, _):
            let kind: GestureSignal.Press
            switch press {
            case .shortPress: kind = .short
            case .hold: kind = .hold
            case .doublePress: kind = .double
            }
            takeCapture(kind)
        case .drag(let action, _, _, let dx, _, _, _):
            // A drag arrives in pieces. How far it went is the sum of them.
            switch action {
            case .down:
                dragTravel = 0
            case .move:
                dragTravel += dx
            case .up:
                let travel = dragTravel + dx
                dragTravel = 0
                act(on: GestureSignal(source: source, kind: .dragEnded(dx: travel)))
            }
        @unknown default:
            // An input a later SDK adds is ignored until `GestureMap` knows it.
            break
        }
    }

    private static func source(of source: InputSource) -> GestureSignal.Source {
        switch source {
        case .captouch: return .temple
        case .neuralBand: return .band
        case .neuralBandDrag: return .bandDrag
        case .captureButton: return .captureButton
        case .actionButton: return .actionButton
        case .unknown: return .unknown
        }
    }

    /// A short press waits a moment for the double press that current firmware sends
    /// after it. See `CapturePressBuffer`.
    private func takeCapture(_ press: GestureSignal.Press) {
        let now = ProcessInfo.processInfo.systemUptime
        for ready in presses.take(press, at: now) {
            act(on: GestureSignal(source: .captureButton, kind: .capture(ready)))
        }
        pressRelease?.cancel()
        pressRelease = nil
        guard let deadline = presses.deadline else { return }
        let wait = max(0, deadline - now)
        pressRelease = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self.pressRelease = nil
            if let ready = self.presses.release(at: ProcessInfo.processInfo.systemUptime + 0.001) {
                self.act(on: GestureSignal(source: .captureButton, kind: .capture(ready)))
            }
        }
    }

    private func act(on signal: GestureSignal) {
        let hadCards = GlassesHUD.shared.hasCards
        GlassesHUD.shared.handle(signal)
        let center = NotificationCenter.default
        switch GestureMap.interpret(signal).gesture {
        case .talkOrConfirm:
            center.post(name: .jarvisTalk, object: nil)
        case .look:
            center.post(name: .jarvisLook, object: nil)
        case .keep:
            center.post(name: .jarvisKeep, object: nil)
        case .note:
            center.post(name: .jarvisNote, object: nil)
        case .dismiss:
            // With no card on the lens to swipe away, a swipe back means "that's enough".
            if !hadCards { center.post(name: .jarvisQuiet, object: nil) }
        case .next, nil:
            break
        }
    }

    // MARK: - Head gestures

    private func attachMotion(to session: DeviceSession) {
        do {
            // DAT Motion (beta): MotionConfiguration sampling rate is a target. Meta docs
            // recommend 30 Hz for responsive head-motion input; each MotionSample field is
            // independently optional (accel m/s² with gravity, gyro rad/s, mag µT, quaternion).
            // No runtime permission. Subscribe to samples before start(); cancel before removeMotion().
            let configuration = MotionConfiguration(samplingRate: .hz30)
            guard let motion = try session.addMotion(configuration: configuration) else { return }
            self.motion = motion
            // State / error publishers do not replay — attach before start(), and retain tokens.
            motionTokens = [
                motion.statePublisher.listen { state in
                    Task { @MainActor in
                        GlassesLink.shared.record("Motion state: \(String(describing: state))")
                    }
                },
                motion.errorPublisher.listen { error in
                    Task { @MainActor in
                        GlassesLink.shared.record("Motion error: \(String(describing: error))")
                    }
                },
            ]
            let samples = motion.samples
            // Readings are worked through off the main actor, and nothing is kept: they
            // are not stored and never leave the phone.
            motionSamples = Task.detached(priority: .utility) {
                var detector = HeadGestureDetector()
                for await sample in samples {
                    guard !Task.isCancelled else { return }
                    // Neural Band motion is a different source; head yes/skip uses glasses IMU only.
                    guard sample.source != .neuralBand else { continue }
                    let turning = sample.gyroscope.map {
                        HeadMotion.Vector(x: Double($0.x), y: Double($0.y), z: Double($0.z))
                    } ?? .zero
                    let reading = HeadMotion(
                        time: Double(sample.timestampNs) / 1_000_000_000,
                        turning: turning,
                        acceleration: sample.accelerometer.map {
                            HeadMotion.Vector(x: Double($0.x), y: Double($0.y), z: Double($0.z))
                        }
                    )
                    // Posture / resume only need accelerometer; gestures need gyroscope swings.
                    await MainActor.run {
                        PresenceContext.shared.ingestMotion(reading, worn: GlassesLink.shared.worn)
                    }
                    guard sample.gyroscope != nil else { continue }
                    guard let answer = detector.take(reading) else { continue }
                    await MainActor.run {
                        NotificationCenter.default.post(name: .jarvisHeadAnswer, object: answer.rawValue)
                    }
                }
            }
            motion.start()
        } catch {
            GlassesLink.shared.record("Head gestures unavailable: \(error.localizedDescription)")
        }
    }

    private func detachMotion(from session: DeviceSession) {
        guard motion != nil else { return }
        forgetMotion()
        do {
            try session.removeMotion()
        } catch {
            GlassesLink.shared.record("Motion not removed: \(error.localizedDescription)")
        }
    }

    private func forgetMotion() {
        motionSamples?.cancel()
        motionSamples = nil
        motionTokens = []
        motion?.stop()
        motion = nil
    }

    // MARK: - Speech on the glasses

    /// Asks the wearer, through the Meta AI app, to let Phoenix Fox use the glasses'
    /// microphone for speech. Called when the switch is turned on, never by itself.
    func requestSpeechPermission() async -> Bool {
        guard let wearables else { return false }
        do {
            if try await wearables.checkPermissionStatus(.microphone) == .granted { return true }
            let granted = try await wearables.requestPermission(.microphone) == .granted
            if granted { settingsChanged() }
            return granted
        } catch {
            GlassesLink.shared.record("Glasses microphone permission: \(error.localizedDescription)")
            return false
        }
    }

    private func attachSpeech(to session: DeviceSession) {
        guard let wearables, !checkingSpeechPermission else { return }
        checkingSpeechPermission = true
        Task {
            // The permission is only checked here. Asking sends the wearer to the Meta AI
            // app, which must not happen in the middle of something else.
            let granted = (try? await wearables.checkPermissionStatus(.microphone)) == .granted
            self.checkingSpeechPermission = false
            guard granted else {
                self.speechRefused = true
                GlassesLink.shared.record("Speech on the glasses needs their microphone. Turn the switch off and on in Glasses settings to be asked.")
                self.reconcile()
                return
            }
            guard self.speech == nil, self.wantsSpeech, !self.paused,
                  let current = self.session, current === session, session.state == .started else { return }
            self.startSpeech(on: session)
        }
    }

    private func startSpeech(on session: DeviceSession) {
        do {
            guard let speech = try session.addSpeech() else { return }
            self.speech = speech
            speechPacer = RestartPacer()
            speechTokens = [
                speech.transcriptionPublisher.listen { result in
                    guard result.isFinal else { return }
                    let text = result.text
                    guard !text.isEmpty else { return }
                    Task { @MainActor in
                        NotificationCenter.default.post(name: .jarvisGlassesTranscript, object: text)
                    }
                },
                speech.statePublisher.listen { state in
                    Task { @MainActor in
                        self.speechChanged(speech, to: state)
                    }
                },
                speech.errorPublisher.listen { error in
                    let reason = error.description
                    let gone = error == .unavailable
                    Task { @MainActor in
                        self.speechFailed(speech, reason: reason, unavailable: gone)
                    }
                },
            ]
            speech.start()
        } catch {
            GlassesLink.shared.record("Speech on the glasses unavailable: \(error.localizedDescription)")
        }
    }

    /// The glasses stop listening by themselves after about a minute of silence, without
    /// an error. While the ear is still wanted it is started again. See `RestartPacer`.
    private func speechChanged(_ changed: Speech, to state: SpeechState) {
        guard let speech, speech === changed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        switch state {
        case .started:
            speechPacer.started(at: now)
        case .stopped:
            guard wantsSpeech, !paused, speechRestart == nil else { return }
            let wait = speechPacer.stopped(at: now)
            speechRestart = Task {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self.speechRestart = nil
                guard let current = self.speech, current === changed, self.wantsSpeech, !self.paused else { return }
                changed.start()
            }
        case .starting, .stopping:
            break
        }
    }

    private func speechFailed(_ failed: Speech, reason: String, unavailable: Bool) {
        guard let speech, speech === failed else { return }
        GlassesLink.shared.record("Speech on the glasses: \(reason)")
        guard unavailable, let session else { return }
        // These glasses, or this firmware, cannot do it. Asking again would not help.
        speechRefused = true
        detachSpeech(from: session)
        reconcile()
    }

    private func detachSpeech(from session: DeviceSession) {
        guard speech != nil else { return }
        forgetSpeech()
        do {
            try session.removeSpeech()
        } catch {
            GlassesLink.shared.record("Speech not removed: \(error.localizedDescription)")
        }
    }

    private func forgetSpeech() {
        speechRestart?.cancel()
        speechRestart = nil
        speechTokens = []
        speech?.stop()
        speech = nil
    }
}

extension Notification.Name {
    static let jarvisVoiceLaunch = Notification.Name("jarvis.voiceLaunch")
    static let jarvisTalk = Notification.Name("jarvis.talk")
    static let jarvisLook = Notification.Name("jarvis.look")
    /// The capture button pressed twice: take a picture and keep it.
    static let jarvisKeep = Notification.Name("jarvis.keep")
    static let jarvisNote = Notification.Name("jarvis.note")
    /// A swipe back with nothing on the lens: stop talking.
    static let jarvisQuiet = Notification.Name("jarvis.quiet")
    /// A nod or a shake of the head. The object is a `HeadAnswer` raw value.
    static let jarvisHeadAnswer = Notification.Name("jarvis.headAnswer")
    /// A finished sentence the glasses turned into text. The object is the sentence.
    static let jarvisGlassesTranscript = Notification.Name("jarvis.glassesTranscript")
}
