// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The shared audio session for the glasses.
//
// HFP (voice mic + short replies) and A2DP (high-quality speaker) cannot run together on
// Meta's glasses. This manager picks one link mode at a time, never both category options
// at once. The HFP route must settle before the camera stream starts, or audio can fail
// with no error. See AudioRoutePolicy and docs/GLASSES_SDK.md.

import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioSessionManager: ObservableObject {
    static let shared = AudioSessionManager()

    private let audioSession = AVAudioSession.sharedInstance()
    private var routeObserver: NSObjectProtocol?

    @Published private(set) var destination: AudioDestination = .phoneSpeaker
    @Published private(set) var linkMode: GlassesLinkMode = .phone
    @Published private(set) var routeDescription = "Input: none, Output: none"
    @Published private(set) var usingGlassesMic = false
    /// True once HFP has been active long enough for the camera to start safely.
    @Published private(set) var hfpSettled = false

    private(set) var currentMode: AudioMode = .inactive
    private var settleTask: Task<Void, Never>?
    private var hfpActivatedAt: Date?

    var onRouteChanged: (() -> Void)?

    enum AudioMode {
        case inactive
        case voiceChat
        case videoChat
        case measurement
    }

    private init() {
        refreshPublished(from: snapshot())
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.routeDidChange() }
        }
    }

    deinit {
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
    }

    // MARK: - Apply

    @discardableResult
    func applyPreferredRoute(
        preferGlassesMic: Bool,
        speakerPreference: SpeakerPreference,
        cameraStreaming: Bool,
        listening: Bool = true,
        longPlayback: Bool = false
    ) throws -> Bool {
        let snap = snapshot()
        let plan = AudioRoutePolicy.plan(
            snapshot: snap,
            preference: speakerPreference,
            preferGlassesMic: preferGlassesMic,
            cameraStreaming: cameraStreaming,
            listening: listening,
            longPlayback: longPlayback
        )
        try apply(plan)
        return plan.preferHFPMic && isBluetoothHFPActive
    }

    func refresh(
        preferGlassesMic: Bool,
        speakerPreference: SpeakerPreference,
        cameraStreaming: Bool,
        listening: Bool = true,
        longPlayback: Bool = false
    ) {
        do {
            _ = try applyPreferredRoute(
                preferGlassesMic: preferGlassesMic,
                speakerPreference: speakerPreference,
                cameraStreaming: cameraStreaming,
                listening: listening,
                longPlayback: longPlayback
            )
        } catch {
            print("[AudioSession] Refresh failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func configureForGlasses() throws -> Bool {
        let settings = SettingsManager.shared.settings
        return try applyPreferredRoute(
            preferGlassesMic: true,
            speakerPreference: settings.speakerPreference == .phone ? .auto : settings.speakerPreference,
            cameraStreaming: GlassesManager.shared.isStreaming,
            listening: true
        )
    }

    func configureForPhone() throws {
        let settings = SettingsManager.shared.settings
        _ = try applyPreferredRoute(
            preferGlassesMic: false,
            speakerPreference: settings.speakerPreference,
            cameraStreaming: GlassesManager.shared.isStreaming,
            listening: true
        )
    }

    func configure(for mode: AudioMode) throws {
        guard mode != currentMode else { return }
        switch mode {
        case .inactive:
            try deactivate()
        case .voiceChat, .videoChat, .measurement:
            let settings = SettingsManager.shared.settings
            _ = try applyPreferredRoute(
                preferGlassesMic: settings.preferGlassesMic,
                speakerPreference: settings.speakerPreference,
                cameraStreaming: GlassesManager.shared.isStreaming
            )
        }
        currentMode = mode
    }

    func deactivate() throws {
        settleTask?.cancel()
        hfpSettled = false
        hfpActivatedAt = nil
        try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        currentMode = .inactive
        linkMode = .phone
    }

    /// Waits until HFP is settled when the current link is the voice link. Call before
    /// starting the camera stream.
    func waitUntilCameraSafe(timeoutSeconds: Double = 2.0) async {
        guard linkMode == .hfpConversation else { return }
        if hfpSettled { return }
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if hfpSettled { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Timed out: still allow the camera, but log it — Meta's silent-fail case.
        print("[AudioSession] HFP settle timed out after \(timeoutSeconds)s; camera may lose audio.")
    }

    var cameraMayStart: Bool {
        AudioRoutePolicy.cameraMayStart(link: linkMode, hfpSettled: hfpSettled)
    }

    // MARK: - Plan

    private func apply(_ plan: AudioSessionPlan) throws {
        // Exclusive options: never HFP and A2DP together.
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if plan.allowHFP { options.insert(.allowBluetoothHFP) }
        if plan.allowA2DP { options.insert(.allowBluetoothA2DP) }
        if plan.defaultToSpeaker { options.insert(.defaultToSpeaker) }

        try audioSession.setCategory(.playAndRecord, mode: .default, options: options)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        if plan.clearSpeakerOverride {
            try? audioSession.overrideOutputAudioPort(.none)
        }

        if plan.preferHFPMic, let hfp = findBluetoothHFPInput() {
            try audioSession.setPreferredInput(hfp)
            usingGlassesMic = true
            beginHFPSettle(seconds: plan.hfpSettleSeconds)
        } else {
            usingGlassesMic = false
            if plan.link != .hfpConversation {
                settleTask?.cancel()
                hfpSettled = plan.link != .hfpConversation
                hfpActivatedAt = nil
            }
        }

        if plan.forceSpeakerOverride {
            let stillQuiet = audioSession.currentRoute.outputs.contains { $0.portType == .builtInReceiver }
            if stillQuiet {
                try? audioSession.overrideOutputAudioPort(.speaker)
            }
        }

        currentMode = .voiceChat
        linkMode = plan.link
        destination = plan.destination
        routeDescription = snapshot().description
        print("[AudioSession] \(plan.destination.title). Link: \(plan.link.title). Mic: \(usingGlassesMic ? "glasses 16 kHz mono" : "phone"). \(routeDescription)")
    }

    private func beginHFPSettle(seconds: Double) {
        hfpSettled = false
        hfpActivatedAt = Date()
        settleTask?.cancel()
        guard seconds > 0 else {
            hfpSettled = true
            return
        }
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.hfpSettled = true
                print("[AudioSession] HFP settled; camera may start.")
            }
        }
    }

    private func routeDidChange() {
        refreshPublished(from: snapshot())
        let settings = SettingsManager.shared.settings
        refresh(
            preferGlassesMic: settings.preferGlassesMic,
            speakerPreference: settings.speakerPreference,
            cameraStreaming: GlassesManager.shared.isStreaming
        )
        onRouteChanged?()
    }

    private func refreshPublished(from snap: AudioRouteSnapshot) {
        routeDescription = snap.description
        let settings = SettingsManager.shared.settings
        let plan = AudioRoutePolicy.plan(
            snapshot: snap,
            preference: settings.speakerPreference,
            preferGlassesMic: settings.preferGlassesMic,
            cameraStreaming: GlassesManager.shared.isStreaming
        )
        destination = plan.destination
        linkMode = plan.link
    }

    // MARK: - Snapshot

    func snapshot() -> AudioRouteSnapshot {
        AudioRouteSnapshot(
            inputs: audioSession.currentRoute.inputs.map(Self.port),
            outputs: audioSession.currentRoute.outputs.map(Self.port),
            availableInputs: (audioSession.availableInputs ?? []).map(Self.port)
        )
    }

    private static func port(_ description: AVAudioSessionPortDescription) -> AudioPort {
        AudioPort(kind: kind(for: description.portType), name: description.portName)
    }

    private static func kind(for type: AVAudioSession.Port) -> AudioPortKind {
        switch type {
        case .bluetoothHFP: return .bluetoothHFP
        case .bluetoothA2DP: return .bluetoothA2DP
        case .builtInSpeaker: return .builtInSpeaker
        case .builtInReceiver: return .builtInReceiver
        case .builtInMic: return .builtInMic
        case .headphones: return .headphones
        default: return .other
        }
    }

    private func findBluetoothHFPInput() -> AVAudioSessionPortDescription? {
        (audioSession.availableInputs ?? []).first { $0.portType == .bluetoothHFP }
    }

    // MARK: - Diagnostics

    var availableInputsDescription: String {
        (audioSession.availableInputs ?? []).map { "\($0.portName)[\($0.portType.rawValue)]" }.joined(separator: ", ")
    }

    var currentRouteDescription: String { snapshot().description }

    var isBluetoothHFPActive: Bool {
        let route = audioSession.currentRoute
        return route.inputs.contains { $0.portType == .bluetoothHFP }
            || route.outputs.contains { $0.portType == .bluetoothHFP }
    }

    var isBluetoothAvailable: Bool {
        snapshot().hasBluetoothHFPInput || snapshot().hasBluetoothOutput
    }

    var isUsingBuiltInMic: Bool {
        audioSession.currentRoute.inputs.contains { $0.portType == .builtInMic }
    }

    var inputSampleRate: Double { audioSession.sampleRate }
    var outputSampleRate: Double { audioSession.sampleRate }

    func logSpeaking() {
        print("[AudioSession] Speaking. \(destination.title). Link \(linkMode.title). \(currentRouteDescription)")
    }

    /// Lines for the Glasses check screen. No secrets.
    var diagnosticLines: [String] {
        [
            destination.title,
            "Link: \(linkMode.title)",
            "Mic: \(usingGlassesMic ? "glasses (mono 16 kHz HFP)" : "phone")",
            "HFP settled: \(hfpSettled ? "yes" : "no")",
            "Camera may start: \(cameraMayStart ? "yes" : "no")",
            routeDescription,
        ]
    }
}
