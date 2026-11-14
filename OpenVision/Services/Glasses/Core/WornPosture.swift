// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Worn / posture context from DAT 1.0 motion (IMU) plus device don state.
//
// Meta's Motion API (MWDATMotion): each `MotionSample` may carry accelerometer (m/s²,
// includes gravity), gyroscope (rad/s), magnetometer (µT), and orientation (quaternion).
// Every sensor field is independently optional. Samples are triggered by accelerometer
// updates in practice; `timestampNs` is device-monotonic. Motion is beta / experimental,
// has no runtime permission, and is owner-build gated in Phoenix Fox.
//
// Used for: head yes/skip gestures (elsewhere), worn continuity, and
// pick-up-where-I-left-off when the glasses are donned again while looking forward.

import Foundation

/// Coarse head posture derived from gravity (accelerometer) or fused orientation.
enum HeadPosture: String, Equatable, Sendable {
    /// Looking roughly level — good moment to resume a paused walk or briefing.
    case level
    /// Chin down toward the chest or a screen in the lap.
    case lookingDown
    /// Chin up.
    case lookingUp
    /// Not enough signal yet.
    case unknown
}

/// One snapshot of worn + posture for features that care about context, not raw IMU.
struct WornPostureContext: Equatable, Sendable {
    var worn: Bool
    var posture: HeadPosture
    /// Degrees from level; positive is chin up when gravity is reliable.
    var pitchDegrees: Double?
    var updatedAt: TimeInterval
}

/// Turns accelerometer (and optional orientation) into a stable posture label.
struct WornPostureTracker: Sendable {
    /// |pitch| under this many degrees counts as level.
    static let levelBandDegrees: Double = 25
    /// How long posture must stay put before we publish a change (seconds).
    static let settle: TimeInterval = 0.35

    private var worn = false
    private var lastPublished = HeadPosture.unknown
    private var candidate = HeadPosture.unknown
    private var candidateSince: TimeInterval = 0
    private var lastPitch: Double?

    mutating func setWorn(_ worn: Bool) {
        self.worn = worn
        if !worn {
            lastPublished = .unknown
            candidate = .unknown
            lastPitch = nil
        }
    }

    /// Feeds one motion sample. Returns a new context when posture or worn state should be noted.
    mutating func take(_ sample: HeadMotion, worn: Bool) -> WornPostureContext? {
        setWorn(worn)
        guard worn else {
            return WornPostureContext(worn: false, posture: .unknown, pitchDegrees: nil, updatedAt: sample.time)
        }
        guard let pitch = pitchDegrees(from: sample) else { return nil }
        lastPitch = pitch
        let next: HeadPosture
        if abs(pitch) <= Self.levelBandDegrees {
            next = .level
        } else if pitch < 0 {
            next = .lookingDown
        } else {
            next = .lookingUp
        }
        if next != candidate {
            candidate = next
            candidateSince = sample.time
            return nil
        }
        guard sample.time - candidateSince >= Self.settle, next != lastPublished else { return nil }
        lastPublished = next
        return WornPostureContext(worn: true, posture: next, pitchDegrees: pitch, updatedAt: sample.time)
    }

    /// Instant pitch from gravity: atan2(forward, up) using the accelerometer as down.
    private func pitchDegrees(from sample: HeadMotion) -> Double? {
        guard let accel = sample.acceleration, let unit = accel.unit else { return nil }
        // Gravity points "down" in the sensor frame. Pitch is how far the forward axis
        // (typically −Z on glasses) tips relative to the horizon. Using the dominant
        // horizontal component keeps this stable when the IMU is rotated in the frame
        // (same issue HeadGestureDetector solves for nods/shakes).
        let down = unit
        let horizontal = (down.x * down.x + down.z * down.z).squareRoot()
        guard horizontal > 0.05 || abs(down.y) > 0.05 else { return nil }
        // Tip-forward (looking down) puts more gravity on −Z → negative pitch.
        // atan2(down.z, −down.y): level gravity (0,−1,0) → 0°; tip-forward z<0 → chin down.
        let pitchRad = atan2(down.z, -down.y)
        return pitchRad * 180 / .pi
    }
}

/// Remembers what the wearer was doing when the glasses came off, so donning them again
/// can offer "pick up where you left off" when posture returns to level.
struct SessionResumeStore: Sendable {
    struct Snapshot: Equatable, Sendable {
        var title: String
        var detail: String
        var savedAt: TimeInterval
    }

    private(set) var pending: Snapshot?

    mutating func remember(title: String, detail: String, at time: TimeInterval) {
        pending = Snapshot(title: title, detail: detail, savedAt: time)
    }

    mutating func clear() { pending = nil }

    /// Returns a resume prompt when the glasses are worn again and the head is level.
    mutating func offer(on context: WornPostureContext) -> Snapshot? {
        guard context.worn, context.posture == .level, let pending else { return nil }
        let saved = pending
        self.pending = nil
        return saved
    }
}
