// OpenVision - GlassesManager.swift
// Singleton manager for Meta Ray-Ban glasses via DAT SDK

import Foundation
import SwiftUI
import CoreMedia
import OSLog
import MWDATCore
import MWDATCamera

/// Manages Meta Ray-Ban glasses registration, connection, and camera streaming
@MainActor
final class GlassesManager: ObservableObject {
    // MARK: - Singleton

    static let shared = GlassesManager()

    // MARK: - Published Properties

    /// Whether the app is registered with Meta AI
    @Published var isRegistered: Bool = false

    /// Currently connected device identifier
    @Published var connectedDevice: DeviceIdentifier?

    /// Number of connected devices
    @Published var connectedDeviceCount: Int = 0

    /// Whether camera streaming is active
    @Published var isStreaming: Bool = false

    /// What the running stream was asked to be. Nil while the camera is off.
    @Published private(set) var streamProfile: StreamProfile?

    /// The wearer paused the session with a tap on the glasses. Frames stop until the
    /// next tap, and the stream must not be restarted meanwhile.
    @Published private(set) var isPaused = false

    /// Last captured video frame
    @Published var lastFrame: UIImage?

    /// When `lastFrame` was received. Lets the live loop tell a fresh frame from a stale one when
    /// the Bluetooth stream throttles under head motion (so it doesn't describe an old view).
    private(set) var lastFrameTime: Date = .distantPast

    /// Last captured photo data
    @Published var lastPhotoData: Data?

    /// Error message for UI display
    @Published var errorMessage: String?

    /// The try at connecting through Meta AI that is under way, or how the last one ended.
    /// Meta AI can refuse without the SDK reporting anything, so this follows the wearer
    /// there and back. See `RegistrationAttempt`.
    @Published private(set) var registration = RegistrationAttempt()

    /// Where the SDK says the connection to Meta AI stands.
    @Published private(set) var registrationStage: RegistrationStage = .notRunning

    /// A connection that was started from the Meta AI app and waits for the wearer's answer.
    /// Nothing is connected until `answerPendingRegistration(approve:)` says so.
    @Published private(set) var pendingRegistration: RegistrationRequest?

    // MARK: - Private Properties

    /// Nil when the glasses SDK did not start. See `WearablesSDK`.
    private var wearables: (any WearablesInterface)? { WearablesSDK.interface }
    // DeviceSession owns the device link, Camera owns the camera hardware, camera.stream
    // carries frames and camera.photo takes stills. Stopping the camera stops both.
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    /// The session belongs to `GlassesControlSession`, which keeps it open when the
    /// camera is done.
    private var borrowedSession = false
    private var streamPurpose: StreamPurpose?
    private var frameGate = FrameGate(perSecond: StreamProfile.baseline.imagesPerSecond)
    private var sessionWatch: Task<Void, Never>?
    private var cameraQueue: Task<Void, Never>?
    /// Why the last attempt to reach the glasses failed, when the glasses said why.
    private var trouble: SessionTrouble?

    // Listener tokens (retained to keep subscriptions active)
    private var registrationTask: Task<Void, Never>?
    private var registrationWait: Task<Void, Never>?
    private var devicesTask: Task<Void, Never>?
    private var stateListenerToken: (any AnyListenerToken)?
    private var videoFrameListenerToken: (any AnyListenerToken)?
    private var photoDataListenerToken: (any AnyListenerToken)?
    private var errorListenerToken: (any AnyListenerToken)?
    private var audioListenerToken: (any AnyListenerToken)?

    // MARK: - Callbacks

    /// Called when a video frame is received
    var onVideoFrame: ((UIImage) -> Void)?

    /// Called with the raw sample buffer for every video frame — used by SessionRecorder to mux
    /// the glasses POV into a movie file without going through UIImage. Independent of `onVideoFrame`.
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?

    /// Called when a photo is captured
    var onPhotoCaptured: ((Data) -> Void)?

    // MARK: - Initialization

    private init() {
        print("[GlassesManager] Initializing")
        if wearables == nil { errorMessage = WearablesSDK.failure }
        setupRegistrationListener()
        setupDevicesListener()
    }

    // MARK: - Registration

    /// Asks the Meta AI app to connect the glasses to Phoenix Fox.
    ///
    /// The outcome is in `registration`, not in a thrown error: Meta AI can refuse a build
    /// and tell the SDK nothing, so the try is judged when the wearer comes back.
    func register() async {
        registration.begin()
        guard let wearables else {
            endRegistration(with: .notRunning(GlassesUnavailable().reason))
            return
        }
        let stage = Self.stage(for: wearables.registrationState)
        registrationStage = stage
        noteRegistration("Connect asked for.")
        if stage == .registered {
            isRegistered = true
            registration.registered()
            return
        }
        do {
            try await wearables.startRegistration()
            startWait(registration.handedOff())
            noteRegistration("Meta AI was asked to open.")
        } catch {
            if let stall = Self.stall(for: error) {
                endRegistration(with: stall)
            } else {
                isRegistered = true
                registration.registered()
                noteRegistration("Already connected.")
            }
        }
    }

    /// The app went to the background. During a try, that means Meta AI opened.
    func appEnteredBackground() {
        registration.enteredBackground()
    }

    /// The app is on the screen again. During a try, the wearer is back from Meta AI.
    func appBecameActive() {
        guard let wait = registration.becameActive() else { return }
        noteRegistration("Back from Meta AI.")
        startWait(wait)
    }

    /// Puts away the trouble from the last try.
    func dismissRegistrationTrouble() {
        registrationWait?.cancel()
        registration.dismiss()
    }

    /// What the last try looked like, for the screen and for whoever is helping.
    var registrationDetails: String {
        registration.details(stage: registrationStage)
    }

    private func startWait(_ wait: RegistrationAttempt.Wait?) {
        guard let wait else { return }
        registrationWait?.cancel()
        registrationWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait.seconds))
            guard !Task.isCancelled else { return }
            self?.registrationWaited(wait)
        }
    }

    private func registrationWaited(_ wait: RegistrationAttempt.Wait) {
        registration.waited(wait)
        if let stall = registration.stall {
            noteRegistration("Not connected after \(Int(wait.seconds)) s: \(stall.title).")
        }
    }

    private func endRegistration(with stall: RegistrationStall) {
        registrationWait?.cancel()
        registration.failed(stall)
        noteRegistration("Stopped: \(stall.title).")
    }

    /// One line in the glasses log. It holds the SDK's state and what happened, and no
    /// names, IDs, tokens or addresses.
    private func noteRegistration(_ what: String) {
        GlassesLink.shared.record("Registration: \(what) \(registrationDetails)")
    }

    private static func stage(for state: RegistrationState) -> RegistrationStage {
        switch state {
        case .unavailable: return .unavailable
        case .available: return .available
        case .registering: return .registering
        case .registered: return .registered
        }
    }

    /// Why the SDK would not start a registration. Nil when it says the glasses are
    /// already connected, which is not a failure.
    private static func stall(for error: any Error) -> RegistrationStall? {
        switch error as? RegistrationError {
        case .alreadyRegistered?: return nil
        case .metaAINotInstalled?: return .notInstalled
        case .networkUnavailable?: return .offline
        case .configurationInvalid?: return .badBuild
        default: return .refused(error.localizedDescription)
        }
    }

    /// Unregister app from Meta AI
    func unregister() async {
        print("[GlassesManager] Starting unregistration")

        await stopStreaming()

        guard let wearables else {
            errorMessage = GlassesUnavailable().reason
            return
        }
        dismissRegistrationTrouble()
        do {
            try await wearables.startUnregistration()
            isRegistered = false
            connectedDevice = nil
            connectedDeviceCount = 0
            errorMessage = nil
            print("[GlassesManager] Unregistration successful")
        } catch {
            errorMessage = "Unregister failed: \(error.localizedDescription)"
            print("[GlassesManager] Unregistration error: \(error)")
        }
    }

    /// Hands off to the Meta AI app to install or update the app's component on the glasses.
    func updateGlassesApp() async {
        guard let wearables else {
            errorMessage = GlassesUnavailable().reason
            return
        }
        do {
            try await wearables.openDATGlassesAppUpdate()
        } catch {
            errorMessage = "Could not open the Meta AI app to update the glasses. \(error.localizedDescription)"
        }
    }

    // MARK: - Meta AI callback

    private var lastCallback: (url: URL, at: Date)?

    /// Finishes a registration or permission round trip when the Meta AI app opens
    /// Phoenix Fox through its universal link.
    func handleCallback(_ url: URL) async {
        // iOS can deliver one link through two routes. The SDK must see it once.
        if let lastCallback, lastCallback.url == url, Date().timeIntervalSince(lastCallback.at) < 2 { return }
        lastCallback = (url, Date())
        guard let wearables else {
            errorMessage = GlassesUnavailable().reason
            GlassesLink.shared.record("Meta AI callback ignored: the glasses SDK is not running.")
            return
        }
        registration.answerBegan()
        var failure: String?
        do {
            let handled = try await wearables.handleUrl(url) { [weak self] request in
                Task { @MainActor in self?.pendingRegistration = request }
            }
            if handled {
                errorMessage = nil
                GlassesLink.shared.record("Meta AI callback handled.")
            } else {
                GlassesLink.shared.record("Opened by a link the glasses SDK did not recognise.")
            }
        } catch {
            failure = error.localizedDescription
            GlassesLink.shared.record("Meta AI callback failed: \(error.localizedDescription)")
        }
        let wasConnecting = registration.isWorking
        startWait(registration.answerEnded(failure: failure))
        if let failure {
            // During a try, the trouble is shown where the wearer tapped. Otherwise it
            // is a message on the Glasses screen.
            if wasConnecting {
                registrationWait?.cancel()
                noteRegistration("Meta AI answered with an error.")
            } else {
                errorMessage = "Meta AI could not finish connecting. \(failure)"
            }
        }
    }

    /// Answers a connection the Meta AI app started. Declining tells Meta AI to drop it.
    func answerPendingRegistration(approve: Bool) async {
        guard let request = pendingRegistration else { return }
        pendingRegistration = nil
        do {
            if approve {
                try await request.continueRegistration()
            } else {
                try await request.cancelRegistration()
            }
        } catch {
            errorMessage = approve
                ? "Connecting to Meta AI failed. \(error.localizedDescription)"
                : "Meta AI did not confirm the cancel. \(error.localizedDescription)"
            GlassesLink.shared.record("Registration request \(approve ? "approve" : "decline") failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Streaming

    /// Turns the glasses camera on for one use. Does nothing when the camera is already on
    /// and good enough for that use.
    ///
    /// What is asked of the glasses depends on the use and on this build: see
    /// `StreamPlanner`. A standard build asks for the same stream for everything.
    func startStreaming(for purpose: StreamPurpose = .still) async {
        await exclusively { await self.begin(purpose) }
    }

    /// One camera operation at a time. Two features that ask for the camera in the same
    /// moment would otherwise each open a session, and the glasses allow one.
    private func exclusively<Result: Sendable>(_ work: @escaping @MainActor () async -> Result) async -> Result {
        let earlier = cameraQueue
        let task = Task { @MainActor () -> Result in
            await earlier?.value
            return await work()
        }
        cameraQueue = Task { _ = await task.value }
        return await task.value
    }

    private func begin(_ purpose: StreamPurpose) async {
        guard let wearables else {
            errorMessage = GlassesUnavailable().reason
            return
        }
        guard isRegistered else {
            errorMessage = "Not registered with Meta AI"
            print("[GlassesManager] Cannot start streaming - not registered")
            return
        }
        // Raw frames only arrive while the app is in the foreground. Background gets
        // HEVC that DAT does not decode, so a look while locked cannot work.
        if UIApplication.shared.applicationState != .active {
            errorMessage = "The glasses camera needs Phoenix Fox open on the screen. Unlock the phone and try again."
            GlassesLink.shared.record("Camera refused: app not in the foreground (raw frames only).")
            return
        }
        // HFP must settle before the camera stream, or glasses audio can fail silently.
        await AudioSessionManager.shared.waitUntilCameraSafe()
        guard let deviceId = connectedDevice else {
            errorMessage = "No glasses connected"
            print("[GlassesManager] Cannot start streaming - no device connected")
            return
        }
        guard var profile = plan(for: purpose) else {
            errorMessage = SessionTrouble.thermal.advice
            GlassesLink.shared.record("Camera refused: the glasses are too hot.")
            return
        }

        if isStreaming {
            // A stream that is already on is left alone unless this use lasts, depends on
            // its frame rate, and the running stream falls short of it.
            guard purpose.replacesLesserStream, let running = streamProfile, !running.covers(profile) else { return }
            // A recording in progress keeps its stream: a new picture size would break the file.
            guard !SessionRecorder.shared.isRecording else { return }
            profile = StreamPlanner.replacement(for: profile, running: running, purpose: purpose, heat: GlassesLink.shared.heat)
            print("[GlassesManager] Replacing the stream (\(running.summary)) for \(purpose.rawValue)")
            GlassesLink.shared.record("Camera restarted for \(purpose.rawValue): \(profile.summary).")
            await closeCamera()
        } else if camera != nil || deviceSession != nil {
            // The last stream ended by itself and left its camera behind.
            await closeCamera()
        }

        print("[GlassesManager] Starting camera stream for device: \(deviceId), \(purpose.rawValue): \(profile.summary)")

        // The SDK's own verdict on whether it can drive this hardware. A mismatch
        // otherwise fails as an opaque "Device unavailable" when the session starts.
        if let device = wearables.deviceForIdentifier(deviceId) {
            print("[GlassesManager] Device \(device.nameOrId()): type=\(device.deviceType()) link=\(device.linkState) compatibility=\(device.compatibility())")
            if device.compatibility() == .deviceUpdateRequired {
                errorMessage = SessionTrouble.firmwareUpdateRequired.advice
            } else if device.compatibility() == .sdkUpdateRequired {
                errorMessage = SessionTrouble.phoneAppTooOld.advice
            }
        } else {
            print("[GlassesManager] deviceForIdentifier returned nil")
        }

        guard await cameraPermitted(wearables) else { return }

        let outcome = await open(profile, for: purpose, on: deviceId, wearables: wearables)
        // If the glasses will not take the larger stream, the one every build has always
        // used is tried before giving up.
        guard outcome == .cameraRefused, profile != .baseline else { return }
        GlassesLink.shared.record("The camera would not start with \(profile.summary). Trying the basic stream.")
        _ = await open(.baseline, for: purpose, on: deviceId, wearables: wearables)
    }

    private enum Opening {
        case opened
        /// No session with the glasses. The reason is in `errorMessage`.
        case noSession
        /// The session is fine and the camera would not join it.
        case cameraRefused
    }

    /// The stream to ask for, or nil when the glasses are too hot.
    private func plan(for purpose: StreamPurpose) -> StreamProfile? {
        StreamPlanner.profile(
            for: purpose,
            capabilities: SettingsManager.shared.glassesCapabilities,
            heat: GlassesLink.shared.heat,
            soundWanted: MicFanout.glasses.hasListeners
        )
    }

    private func cameraPermitted(_ wearables: any WearablesInterface) async -> Bool {
        do {
            var status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                print("[GlassesManager] Requesting camera permission...")
                status = try await wearables.requestPermission(.camera)
            }
            guard status == .granted else {
                errorMessage = "Camera permission denied"
                print("[GlassesManager] Camera permission not granted")
                return false
            }
            return true
        } catch {
            errorMessage = "Permission error: \(error.localizedDescription)"
            print("[GlassesManager] Permission error: \(error)")
            return false
        }
    }

    /// Opens a session if one is needed, adds the camera, and starts the stream.
    private func open(
        _ profile: StreamProfile,
        for purpose: StreamPurpose,
        on deviceId: DeviceIdentifier,
        wearables: any WearablesInterface
    ) async -> Opening {
        trouble = nil
        guard let session = await acquireSession(on: deviceId, wearables: wearables) else { return .noSession }
        let config = Self.configuration(for: profile)
        var cam: Camera?
        do {
            cam = try session.addCamera(config: config)
        } catch {
            note(error, doing: "add the camera")
        }
        if cam == nil, borrowedSession {
            // The session that was already open for the controls would not take a camera.
            // It is closed, and the camera gets a session of its own, as it always had.
            GlassesLink.shared.record("The open session refused the camera. Starting a fresh one.")
            deviceSession = nil
            borrowedSession = false
            await GlassesControlSession.shared.suspendForCamera()
            if let own = await startOwnSession(on: deviceId, wearables: wearables) {
                deviceSession = own
                watchOwnSession(own)
                do {
                    cam = try own.addCamera(config: config)
                } catch {
                    note(error, doing: "add the camera")
                }
            }
        }
        guard let cam else {
            if errorMessage == nil { errorMessage = "Failed to attach camera to device session" }
            print("[GlassesManager] addCamera returned nil")
            let hadSession = deviceSession != nil
            await closeCamera()
            return hadSession ? .cameraRefused : .noSession
        }
        camera = cam
        streamProfile = profile
        streamPurpose = purpose
        frameGate = FrameGate(perSecond: profile.imagesPerSecond)
        isPaused = false

        setupStreamListeners(stream: cam.stream, sound: profile.sound != nil)
        cam.stream.start()
        isStreaming = true
        GlassesLink.shared.noteStreaming(true)
        GlassesLink.shared.record("Camera on: \(profile.summary).")
        print("[GlassesManager] Streaming started successfully")
        return .opened
    }

    /// The session the camera will use: the one already open for the controls when there
    /// is one, and otherwise a new one.
    private func acquireSession(on deviceId: DeviceIdentifier, wearables: any WearablesInterface) async -> DeviceSession? {
        if let shared = await GlassesControlSession.shared.lendForCamera() {
            deviceSession = shared
            borrowedSession = true
            return shared
        }
        await GlassesControlSession.shared.suspendForCamera()
        borrowedSession = false
        var session = await startOwnSession(on: deviceId, wearables: wearables)
        if session == nil, trouble == .sessionAlreadyExists {
            // The last session was still closing. It needs a moment, not a message.
            try? await Task.sleep(for: .milliseconds(700))
            session = await startOwnSession(on: deviceId, wearables: wearables)
        }
        guard let session else {
            GlassesControlSession.shared.resumeAfterCamera()
            return nil
        }
        deviceSession = session
        watchOwnSession(session)
        return session
    }

    /// Creates a session and waits for it to start. Nil when it did not, with the reason
    /// in `errorMessage`.
    private func startOwnSession(on deviceId: DeviceIdentifier, wearables: any WearablesInterface) async -> DeviceSession? {
        // SpecificDeviceSelector stays the more reliable choice over AutoDeviceSelector.
        let selector = SpecificDeviceSelector(device: deviceId)
        do {
            let session = try wearables.createSession(deviceSelector: selector)
            // Order matters: the session must be started before addCamera, which returns
            // nil on an idle session. The state stream is taken before start() so the
            // change to started cannot be missed.
            let stateStream = session.stateStream()
            // A session can give up while starting and say why only on its error stream.
            let sessionErrorTask = Task { [weak self] in
                for await error in session.errorStream() {
                    print("[GlassesManager] Device session error: \(error) — \(error.description)")
                    await MainActor.run { self?.note(error, doing: "start the session") }
                }
            }
            defer { sessionErrorTask.cancel() }
            print("[GlassesManager] Starting device session...")
            try session.start()

            let started = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await state in stateStream {
                        print("[GlassesManager] Device session state: \(state)")
                        if state == .started { return true }
                        if state == .stopped { return false }
                    }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            guard started else {
                if trouble == nil { errorMessage = "Device session did not start (timeout)" }
                print("[GlassesManager] Device session failed to reach .started")
                dumpSDKLogs(since: 30)
                session.stop()
                return nil
            }
            return session
        } catch {
            note(error, doing: "start the session")
            print("[GlassesManager] Session start error: \(error)")
            return nil
        }
    }

    /// Follows a session this manager opened, for the changes that are not errors: the
    /// wearer pausing it with a tap on the touchpad, or ending it with a long press.
    private func watchOwnSession(_ session: DeviceSession) {
        sessionWatch?.cancel()
        let states = session.stateStream()
        sessionWatch = Task { [weak self] in
            for await state in states {
                guard !Task.isCancelled else { return }
                await self?.sessionChanged(to: state, session: session)
            }
        }
    }

    /// Called for the session the camera is using, whoever opened it.
    func sessionChanged(to state: DeviceSessionState, session: DeviceSession) async {
        guard let current = deviceSession, current === session else { return }
        switch state {
        case .paused:
            // Frames stop while paused and come back by themselves. Restarting now would
            // fight the wearer, who paused it.
            guard !isPaused else { return }
            isPaused = true
            GlassesLink.shared.record("Session paused from the glasses. Frames resume when it is tapped again.")
        case .started:
            guard isPaused else { return }
            isPaused = false
            GlassesLink.shared.record("Session resumed.")
        case .stopped:
            await exclusively {
                // Checked again here: by the time this runs, a new session may be in use.
                guard let current = self.deviceSession, current === session else { return }
                GlassesLink.shared.record("The glasses ended the session. Camera off.")
                await self.closeCamera()
            }
        default:
            break
        }
    }

    /// Stop camera streaming
    func stopStreaming() async {
        await exclusively {
            guard self.isStreaming || self.camera != nil || self.deviceSession != nil else { return }
            print("[GlassesManager] Stopping camera stream")
            await self.closeCamera()
            print("[GlassesManager] Streaming stopped")
        }
    }

    /// Stops the camera and lets go of its session. Safe to call in any state.
    private func closeCamera() async {
        sessionWatch?.cancel()
        sessionWatch = nil
        camera?.stop()          // cascades to the stream and the photo capability
        let wasBorrowed = borrowedSession
        if !wasBorrowed { deviceSession?.stop() }

        cleanupStreamListeners()
        camera = nil
        deviceSession = nil
        borrowedSession = false
        isStreaming = false
        isPaused = false
        streamProfile = nil
        streamPurpose = nil
        lastFrame = nil
        lastFrameTime = .distantPast
        GlassesLink.shared.noteStreaming(false)
        if wasBorrowed {
            GlassesControlSession.shared.cameraReturned()
        } else {
            GlassesControlSession.shared.resumeAfterCamera()
        }
    }

    /// Capture a photo from the glasses camera
    func capturePhoto() async {
        guard isStreaming, let stream = camera?.stream else {
            errorMessage = "Streaming must be active to capture photos"
            return
        }

        print("[GlassesManager] Capturing photo")

        // Failures arrive as StreamError.photoCaptureFailed on the error publisher, which
        // setupStreamListeners already routes to errorMessage.
        if !stream.capturePhoto(format: .jpeg) {
            errorMessage = "Failed to start photo capture"
            print("[GlassesManager] capturePhoto returned false")
        }
    }

    private static func configuration(for profile: StreamProfile) -> StreamConfiguration {
        let resolution: StreamingResolution
        switch profile.resolution {
        case .low: resolution = .low
        case .medium: resolution = .medium
        case .high: resolution = .high
        }
        let audio: AudioCodec?
        switch profile.sound {
        case nil: audio = nil
        case .speech?: audio = .pcm(sampleRate: .rate16000, numberOfChannels: 1)
        case .full?: audio = .pcm(sampleRate: .rate48000, numberOfChannels: 1)
        }
        // Raw frames. The compressed stream keeps arriving with the phone locked, but
        // iOS does not let an app decode video in the background, so nothing here could
        // use it. See docs/GLASSES_SDK.md.
        return StreamConfiguration(videoCodec: .raw, audioCodec: audio, resolution: resolution, frameRate: UInt(profile.frameRate))
    }

    // MARK: - What the glasses report while the camera is on

    /// The glasses got hotter or cooler while the camera may be on.
    func heatChanged(to heat: GlassesHeat) async {
        await exclusively { await self.adjust(to: heat) }
    }

    private func adjust(to heat: GlassesHeat) async {
        guard isStreaming, let purpose = streamPurpose, let running = streamProfile else { return }
        guard let allowed = plan(for: purpose) else {
            if SessionRecorder.shared.isRecording { SessionRecorder.shared.stop() }
            await closeCamera()
            errorMessage = SessionTrouble.thermal.advice
            TTSService.shared.announce("The glasses are too hot, so the camera is off.", urgent: true)
            return
        }
        // A recording keeps the stream it started with: changing the picture size in the
        // middle would break the file. The glasses stop it themselves if they must.
        guard purpose != .recording, !SessionRecorder.shared.isRecording else { return }
        // Only ever down. When the glasses cool, the next use of the camera gets the
        // better stream; restarting a stream that works is not worth the gap.
        guard heat >= .moderate, allowed != running, running.covers(allowed),
              let deviceId = connectedDevice, let wearables else { return }
        GlassesLink.shared.record("The glasses are warm. The camera drops to \(allowed.summary).")
        await closeCamera()
        _ = await open(allowed, for: purpose, on: deviceId, wearables: wearables)
    }

    // MARK: - Photos from the whole sensor

    /// What a still is for, which decides how large it is.
    enum StillUse: Sendable {
        /// A picture to keep: the whole sensor, 4032 by 3024, at the best quality.
        case keepsake
        /// Text to read: large enough for small print, and half the wait.
        case reading

        var resolution: PhotoResolution { self == .keepsake ? .full : .large }
        var quality: PhotoQuality { .high }
        /// The longest the whole picture may take to arrive.
        var patience: TimeInterval { self == .keepsake ? 25 : 14 }
    }

    /// Takes one photo with the camera's photo capability, which uses the whole sensor.
    ///
    /// Returns nil when this build may not use it, when the camera is busy streaming, or
    /// when the glasses did not deliver. The caller then takes a frame from the stream,
    /// which is smaller and has always worked.
    func captureStill(_ use: StillUse) async -> Data? {
        // Full-sensor photo is experimental in DAT 1.0.1 and Meta says apps using it
        // cannot ship to the App Store yet. Only the owner/TestFlight build may try it;
        // store builds always use a stream frame.
        guard BuildFlavor.current.allowsExperimental,
              SettingsManager.shared.glassesCapabilities.highResolutionStills else { return nil }
        return await exclusively { await self.still(use) }
    }

    private func still(_ use: StillUse) async -> Data? {
        guard let wearables, isRegistered, let deviceId = connectedDevice else { return nil }
        // The stream and the photo capability cannot both have the camera.
        guard !isStreaming, camera == nil else { return nil }
        // The large transfer is the hottest thing the glasses do for this app.
        guard GlassesLink.shared.heat < .severe else { return nil }
        // A photo that fails is not the wearer's problem to read about: the caller falls
        // back to the stream, and whatever was on screen before stays.
        let shown = errorMessage
        defer { errorMessage = shown }
        guard await cameraPermitted(wearables) else { return nil }

        trouble = nil
        guard let session = await acquireSession(on: deviceId, wearables: wearables) else { return nil }
        var data: Data?
        // Meta's guidance: the photo capability sometimes fails to start and works the
        // next time. One more try with a new camera, and then the stream.
        for attempt in 1...2 {
            data = await takeStill(use, on: session)
            if data != nil || isPaused { break }
            GlassesLink.shared.record("Photo attempt \(attempt) gave nothing.")
        }
        await closeCamera()
        if let data {
            GlassesLink.shared.record("Photo: \(data.count / 1024) KB.")
        }
        return data
    }

    private enum StillEvent: Sendable {
        case state(PhotoState)
        case picture(Data)
        case progress
        case failed(String)
        case tick
    }

    private func takeStill(_ use: StillUse, on session: DeviceSession) async -> Data? {
        let cam: Camera
        do {
            guard let added = try session.addCamera() else { return nil }
            cam = added
        } catch {
            GlassesLink.shared.record("Photo camera not added: \(error.localizedDescription)")
            return nil
        }
        camera = cam
        defer {
            cam.stop()
            if camera === cam { camera = nil }
        }

        let photo = cam.photo
        let (events, feed) = AsyncStream.makeStream(of: StillEvent.self)
        // The publishers do not replay, so every listener is in place before start().
        let tokens: [any AnyListenerToken] = [
            photo.statePublisher.listen { feed.yield(.state($0)) },
            photo.photoDataPublisher.listen { feed.yield(.picture($0.imageData)) },
            photo.transferProgressPublisher.listen { _ in feed.yield(.progress) },
            photo.errorPublisher.listen { feed.yield(.failed($0.description)) },
        ]
        let clock = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                feed.yield(.tick)
            }
        }
        defer {
            clock.cancel()
            feed.finish()
            withExtendedLifetime(tokens) {}
        }
        photo.start()

        let began = Date()
        var asked: Date?
        var lastSign = Date()
        var wasStarting = false
        for await event in events {
            switch event {
            case .state(.starting):
                wasStarting = true
            case .state(.started):
                // "Started" can be published more than once. One capture is asked for.
                guard asked == nil else { continue }
                asked = Date()
                lastSign = Date()
                photo.capturePhoto(resolution: use.resolution, quality: use.quality)
            case .state(.stopped):
                // Back to stopped after starting means the capability did not come up.
                if wasStarting || asked != nil { return nil }
            case .state:
                break
            case .picture(let data):
                // A press of the wearer's own shutter arrives here too. Only a picture
                // that follows this request is taken as its answer.
                guard asked != nil, !data.isEmpty else { continue }
                return data
            case .progress:
                lastSign = Date()
            case .failed(let reason):
                GlassesLink.shared.record("Photo failed: \(reason)")
                return nil
            case .tick:
                let now = Date()
                if isPaused { return nil }
                if asked == nil, now.timeIntervalSince(began) > 6 { return nil }
                if asked != nil, now.timeIntervalSince(lastSign) > 8 { return nil }
                if now.timeIntervalSince(began) > use.patience { return nil }
            }
        }
        return nil
    }

    // MARK: - Session problems

    /// Records why the glasses refused, in words the wearer can act on.
    private func note(_ error: any Error, doing what: String) {
        let found = Self.trouble(for: error)
        trouble = found
        errorMessage = found == .other ? "Could not \(what). \(error.localizedDescription)" : found.advice
        GlassesLink.shared.record("Could not \(what): \(error.localizedDescription)")
    }

    private static func trouble(for error: any Error) -> SessionTrouble {
        guard let error = error as? DeviceSessionError else { return .other }
        switch error {
        case .noEligibleDevice: return .noEligibleDevice
        case .sessionAlreadyExists, .capabilityAlreadyActive: return .sessionAlreadyExists
        case .thermalCritical, .thermalEmergency: return .thermal
        case .peakPowerShutdown, .batteryCritical: return .power
        case .datAppOnTheGlassesUpdateRequired: return .glassesAppUpdateRequired
        case .dwaUnavailable: return .metaAIUnavailable
        case .insufficientSDKVersion: return .phoneAppTooOld
        default: return .other
        }
    }

    /// Hands off to the Meta AI app to update the glasses themselves.
    func updateGlassesFirmware() async {
        guard let wearables else {
            errorMessage = GlassesUnavailable().reason
            return
        }
        do {
            try await wearables.openFirmwareUpdate()
        } catch {
            errorMessage = "Could not open the Meta AI app to update the glasses. \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func setupRegistrationListener() {
        guard let wearables else { return }
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                await MainActor.run {
                    let stage = Self.stage(for: state)
                    let changed = stage != self.registrationStage
                    self.registrationStage = stage
                    if stage == .registered {
                        self.isRegistered = true
                        self.registrationWait?.cancel()
                        self.registration.registered()
                        GlassesLink.shared.noteRegistration(true)
                    } else {
                        self.isRegistered = false
                        GlassesLink.shared.noteRegistration(false)
                    }
                    if changed { self.noteRegistration("State changed.") }
                    print("[GlassesManager] Registration state: \(stage.rawValue)")
                }
            }
        }
    }

    private func setupDevicesListener() {
        guard let wearables else { return }
        devicesTask = Task {
            for await devices in wearables.devicesStream() {
                await MainActor.run {
                    self.connectedDeviceCount = devices.count
                    self.connectedDevice = devices.first
                    GlassesLink.shared.noteDeviceCount(devices.count)
                    if let id = devices.first {
                        GlassesControlSession.shared.deviceAppeared(id)
                    } else {
                        GlassesControlSession.shared.deviceDisappeared()
                    }
                    print("[GlassesManager] Devices updated: \(devices.count) connected")
                }
            }
        }
    }

    private func setupStreamListeners(stream: MWDATCamera.Stream, sound: Bool) {
        stateListenerToken = stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self, self.camera?.stream === stream else { return }
                switch state {
                case .streaming:
                    self.isStreaming = true
                case .stopped:
                    self.isStreaming = false
                default:
                    break
                }
            }
        }

        videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
            Task { @MainActor in self?.take(frame) }
        }

        // Sound from the glasses microphones, when this stream carries it. The buffer goes
        // straight to whoever listens, on the thread it arrived on.
        if sound {
            let fanout = MicFanout.glasses
            fanout.restart()
            audioListenerToken = stream.audioFramePublisher.listen { frame in
                fanout.send(frame.pcmBuffer)
            }
        }

        photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor in
                let data = photoData.data
                self?.lastPhotoData = data
                self?.onPhotoCaptured?(data)
                print("[GlassesManager] Photo captured: \(data.count) bytes")
            }
        }

        errorListenerToken = stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                // Raw frames stop by design when the app leaves the foreground, and the
                // SDK reports that as an error. Only errors that happen while the wearer
                // is looking at the app are shown.
                if UIApplication.shared.applicationState == .active {
                    self?.errorMessage = Self.advice(for: error)
                }
                GlassesLink.shared.record("Stream error: \(error.description)")
                print("[GlassesManager] Stream error: \(error)")
            }
        }
    }

    /// One frame from the glasses. Every frame goes to a recording. Only as many as the
    /// profile allows are turned into images, which is the costly part at 30 a second.
    private func take(_ frame: VideoFrame) {
        onVideoSampleBuffer?(frame.sampleBuffer)
        guard frameGate.admit(at: ProcessInfo.processInfo.systemUptime) else { return }
        if let image = frame.makeUIImage() {
            lastFrame = image
            lastFrameTime = Date()
            onVideoFrame?(image)
        }
    }

    private static func advice(for error: StreamError) -> String {
        switch error {
        case .thermalHot: return SessionTrouble.thermal.advice
        case .batteryLow, .peakPowerLimit: return SessionTrouble.power.advice
        case .hingesClosed: return "The glasses are folded. Open them to use the camera."
        case .permissionDenied: return "Phoenix Fox is not allowed to use the glasses camera. Allow it in the Meta AI app."
        case .deviceNotFound, .deviceNotConnected: return SessionTrouble.noEligibleDevice.advice
        default: return error.localizedDescription
        }
    }

    /// TEMP DIAGNOSTIC (issue #55 follow-up): the DAT SDK logs its teardown reasons via OSLog,
    /// which `devicectl --console` can't see. The app CAN read its own process's entries, so on
    /// session failure dump every non-Apple subsystem line from the last `seconds` to stdout.
    private func dumpSDKLogs(since seconds: TimeInterval) {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-seconds))
            let entries = try store.getEntries(at: position)
            print("[GlassesManager] ===== SDK log dump (last \(Int(seconds))s) =====")
            for entry in entries {
                guard let log = entry as? OSLogEntryLog else { continue }
                let sub = log.subsystem
                guard !sub.isEmpty, !sub.hasPrefix("com.apple") else { continue }
                print("[SDKLOG] \(sub)/\(log.category) [\(log.level.rawValue)] \(log.composedMessage)")
            }
            print("[GlassesManager] ===== end SDK log dump =====")
        } catch {
            print("[GlassesManager] OSLogStore dump failed: \(error)")
        }
    }

    private func cleanupStreamListeners() {
        stateListenerToken = nil
        videoFrameListenerToken = nil
        photoDataListenerToken = nil
        errorListenerToken = nil
        audioListenerToken = nil
    }
}
