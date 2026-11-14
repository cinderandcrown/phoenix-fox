// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Session state machine required by the Meta Glasses Swift engineering standard
// (SKILL §4): idle → registering/connecting → permissionRequired → ready →
// starting → active → stopping → ready, plus unavailable / interrupted /
// failed / recovering. Illegal transitions fail gracefully. DAT types stay
// behind the Wearables adapter; this file is pure Swift so unit tests do not
// need the SDK.

import Foundation

/// App-level wearable session phase. Distinct from Meta's `DeviceSessionState`
/// (idle/starting/started/…) and from `RegistrationAttempt.Phase`.
enum WearableSessionPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case registering
    case connecting
    case permissionRequired
    case ready
    case starting
    case active
    case stopping
    case unavailable
    case interrupted
    case failed
    case recovering
}

/// What the wearer should do next from this phase (SKILL §7: every UX state
/// needs a purposeful next action).
struct WearableSessionNextAction: Equatable, Sendable {
    let title: String
    let detail: String
}

extension WearableSessionPhase {
    var nextAction: WearableSessionNextAction {
        switch self {
        case .idle:
            return .init(title: "Connect glasses", detail: "Open Meta AI pairing from Settings → Glasses.")
        case .registering:
            return .init(title: "Finish in Meta AI", detail: "Approve Phoenix Fox, then return here.")
        case .connecting:
            return .init(title: "Wait", detail: "Looking for paired glasses.")
        case .permissionRequired:
            return .init(title: "Allow camera", detail: "Grant camera (and mic if asked) when Meta AI prompts.")
        case .ready:
            return .init(title: "Start when needed", detail: "Say the wake word or ask for a look. Capture light stays off until then.")
        case .starting:
            return .init(title: "Wait", detail: "Opening the glasses session.")
        case .active:
            return .init(title: "Stop when done", detail: "Say stop, tap Stop, or close the session. Capture light is on.")
        case .stopping:
            return .init(title: "Wait", detail: "Closing the session and releasing the camera.")
        case .unavailable:
            return .init(title: "Use phone-only", detail: "Glasses toolkit is not running in this build or environment.")
        case .interrupted:
            return .init(title: "Resume", detail: "Unlock the phone or end the interruption, then start again.")
        case .failed:
            return .init(title: "Retry", detail: "Check Meta AI, Developer Mode, and glasses power, then try again.")
        case .recovering:
            return .init(title: "Wait", detail: "Reconnecting after a disconnect or interrupt.")
        }
    }
}

/// Pure transition table. Illegal edges leave the phase unchanged and return an error.
struct WearableSessionMachine: Equatable, Sendable {
    enum TransitionError: Equatable, Error, CustomStringConvertible {
        case illegal(from: WearableSessionPhase, to: WearableSessionPhase)

        var description: String {
            switch self {
            case .illegal(let from, let to):
                return "Illegal wearable session transition: \(from.rawValue) → \(to.rawValue)"
            }
        }
    }

    private(set) var phase: WearableSessionPhase

    init(phase: WearableSessionPhase = .idle) {
        self.phase = phase
    }

    /// Allowed successors for each phase. Side states (unavailable / interrupted /
    /// failed / recovering) can re-enter the main path at ready or idle.
    static func allows(_ from: WearableSessionPhase, to: WearableSessionPhase) -> Bool {
        if from == to { return true }
        switch from {
        case .idle:
            return [.registering, .connecting, .unavailable, .failed].contains(to)
        case .registering:
            return [.connecting, .permissionRequired, .ready, .failed, .unavailable, .idle].contains(to)
        case .connecting:
            return [.permissionRequired, .ready, .failed, .unavailable, .recovering, .idle].contains(to)
        case .permissionRequired:
            return [.ready, .failed, .idle, .unavailable].contains(to)
        case .ready:
            return [.starting, .interrupted, .failed, .unavailable, .idle, .registering, .connecting].contains(to)
        case .starting:
            return [.active, .failed, .interrupted, .stopping, .ready].contains(to)
        case .active:
            return [.stopping, .interrupted, .failed, .recovering].contains(to)
        case .stopping:
            return [.ready, .failed, .idle].contains(to)
        case .unavailable:
            return [.idle, .registering, .ready].contains(to)
        case .interrupted:
            return [.recovering, .ready, .stopping, .failed, .idle].contains(to)
        case .failed:
            return [.idle, .recovering, .registering, .ready].contains(to)
        case .recovering:
            return [.ready, .connecting, .failed, .idle].contains(to)
        }
    }

    @discardableResult
    mutating func transition(to next: WearableSessionPhase) -> Result<WearableSessionPhase, TransitionError> {
        guard Self.allows(phase, to: next) else {
            return .failure(.illegal(from: phase, to: next))
        }
        phase = next
        return .success(phase)
    }
}
