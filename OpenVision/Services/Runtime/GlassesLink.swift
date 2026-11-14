// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Jarvis - GlassesLink.swift
// Connection state the UI can show. The SDK pushes devices; this records the phase,
// battery, and a short log. Reconnect is the SDK's devicesStream coming back, plus a
// backoff note so a drop is visible instead of silent.

import Foundation
import MWDATCore
import OSLog

@MainActor
final class GlassesLink: ObservableObject {
    static let shared = GlassesLink()

    enum Phase: Equatable, CustomStringConvertible {
        case unregistered
        case waiting
        case connected
        case streaming
        case reconnecting(attempt: Int)
        case failed(String)

        var description: String {
            switch self {
            case .unregistered: return "Not paired"
            case .waiting: return "Waiting for glasses"
            case .connected: return "Glasses connected"
            case .streaming: return "Camera on"
            case .reconnecting(let n): return "Reconnecting (\(n))"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var phase: Phase = .unregistered
    @Published private(set) var battery: Int?
    @Published private(set) var charging = false
    @Published private(set) var worn = false
    @Published private(set) var hingeOpen = false
    @Published private(set) var thermal = "unknown"
    /// What the reported temperature means for the camera. See `StreamPlanner`.
    @Published private(set) var heat: GlassesHeat = .normal
    /// The glasses say they are not being worn. False when they do not say.
    @Published private(set) var takenOff = false
    @Published private(set) var hardware = "Unknown glasses"
    @Published private(set) var displayCapable = false
    @Published private(set) var logs: [String] = []

    private let log = Logger(subsystem: "llc.cinderandcrown.phoenixfox", category: "glasses")
    private var sawDevice = false
    private var attempt = 0

    private init() {}

    func noteRegistration(_ registered: Bool) {
        if !registered {
            phase = .unregistered
        } else if phase == .unregistered {
            phase = .waiting
        }
    }

    func noteDeviceCount(_ count: Int) {
        if count > 0 {
            sawDevice = true
            attempt = 0
            if phase != .streaming { phase = .connected }
        } else if sawDevice {
            attempt += 1
            phase = attempt > 5 ? .failed("Glasses stayed disconnected") : .reconnecting(attempt: attempt)
            record("Link dropped, attempt \(attempt)")
        } else if phase != .unregistered {
            phase = .waiting
        }
    }

    func noteStreaming(_ streaming: Bool) {
        if streaming {
            phase = .streaming
        } else if case .streaming = phase {
            phase = .connected
        }
    }

    func apply(_ state: DeviceState) {
        battery = state.batteryLevel
        charging = state.chargingState == .charging
        hingeOpen = state.hingeState == .open
        thermal = String(describing: state.thermalLevel)

        let wasWorn = worn
        let wasOff = takenOff
        worn = state.donState == .donned
        takenOff = state.donState == .doffed
        if takenOff, !wasOff {
            GlassesControlSession.shared.glassesTakenOff()
            PresenceContext.shared.noteWorn(false)
        }
        if worn, !wasWorn {
            // Current firmware stops sending button and touchpad presses after the
            // glasses are taken off and put back on. The controls are attached again.
            GlassesControlSession.shared.glassesPutOn()
            PresenceContext.shared.noteWorn(true)
        }

        let now = Self.heat(for: state.thermalLevel)
        guard now != heat else { return }
        let rising = now > heat
        heat = now
        switch now {
        case .normal, .light:
            if !rising { record("The glasses have cooled (\(thermal)).") }
        case .moderate:
            record("The glasses are warm (\(thermal)). The camera uses a lighter stream.")
        case .severe:
            record("The glasses are hot (\(thermal)). The camera uses its lightest stream, and large photos wait.")
        case .critical:
            record("The glasses are too hot (\(thermal)). The camera stays off until they cool.")
        }
        Task { await GlassesManager.shared.heatChanged(to: now) }
        GlassesControlSession.shared.heatChanged(to: now)
    }

    /// Meta's guidance for each level: reduce optional work at moderate, shed load at
    /// severe, and treat the glasses as unavailable from critical on.
    private static func heat(for level: ThermalLevel) -> GlassesHeat {
        switch level {
        case .unknown, .none: return .normal
        case .light: return .light
        case .moderate: return .moderate
        case .severe: return .severe
        case .critical, .emergency, .shutdown: return .critical
        }
    }

    func noteHardware(type: DeviceType, display: Bool) {
        hardware = GlassesProductTarget.label(type)
        displayCapable = display
        if GlassesProductTarget.isV1Target(type) {
            record("v1 target: Meta Glasses Adventurer. Audio and camera. No in-lens display.")
        } else if display {
            record("Display glasses (\(hardware)). HUD is optional and not required for v1.")
        } else {
            record("Audio-only glasses (\(hardware)).")
        }
    }

    func record(_ line: String) {
        log.info("\(line, privacy: .public)")
        logs.append(line)
        if logs.count > 80 { logs.removeFirst(logs.count - 80) }
    }
}
