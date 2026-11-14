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
    @Published private(set) var hardware = "Unknown glasses"
    @Published private(set) var displayCapable = false
    @Published private(set) var logs: [String] = []

    private let log = Logger(subsystem: "llc.cinderandcrown.jarvis", category: "glasses")
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
        worn = state.donState == .donned
        hingeOpen = state.hingeState == .open
        thermal = String(describing: state.thermalLevel)
        if state.thermalLevel == .severe || state.thermalLevel == .critical || state.thermalLevel == .emergency {
            record("Glasses are hot (\(thermal)). Camera stays off until they cool.")
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
