// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Chooses what to ask of the glasses camera for each thing Phoenix Fox does with it.
//
// Meta's toolkit streams at 360 by 640, 504 by 896, or 720 by 1280, at 2, 7, 15, 24, or
// 30 frames a second, and nothing in between. A lower frame rate leaves more of the
// Bluetooth link for each frame, so a still is sharper at 7 frames a second than at 30.
// The fastest stream is therefore not the best one for every use, and this file picks
// per use.
//
// The glasses get hot when they stream. Each step of heat they report takes the plan
// down, and at "critical" there is no plan: the camera is refused until they cool.

import Foundation

/// Why the camera is on.
enum StreamPurpose: String, Sendable, CaseIterable {
    /// One look: a photo for a question, a label, a page.
    case still
    /// Watch mode: a frame every few seconds, compared with the last.
    case watch
    /// Guide mode: hazards ahead of someone walking. Old frames are dangerous.
    case guide
    /// Smart capture: receipts, cards, and whiteboards, kept when they are sharp.
    case smartCapture
    /// Live video with the assistant.
    case liveVideo
    /// A recording saved to Photos.
    case recording
    /// Look to Talk: a screen across a desk, read about once a second.
    case lookToTalk
}

extension StreamPurpose {
    /// Whether this use is worth a restart of a camera that is already on but falls short
    /// of it. A restart costs about a second without frames.
    ///
    /// The uses that last and depend on their frame rate say yes: a walker's hazards, a
    /// conversation about moving video, a recording. One look, a watch that samples every
    /// few seconds, and a document that waits to be sharp take the stream as they find it.
    var replacesLesserStream: Bool {
        switch self {
        case .guide, .liveVideo, .recording: return true
        case .still, .watch, .smartCapture, .lookToTalk: return false
        }
    }
}

/// How hot the glasses say they are, reduced to what Phoenix Fox does about it.
enum GlassesHeat: Int, Comparable, Sendable {
    /// Cool, or not reported.
    case normal
    /// Warm. Nothing changes yet.
    case light
    /// Meta's guidance: reduce optional work.
    case moderate
    /// Meta's guidance: shed load.
    case severe
    /// Meta's guidance: treat the device as unavailable.
    case critical

    static func < (a: GlassesHeat, b: GlassesHeat) -> Bool { a.rawValue < b.rawValue }
}

struct StreamProfile: Equatable, Sendable {
    enum Resolution: Int, Comparable, Sendable {
        case low, medium, high

        static func < (a: Resolution, b: Resolution) -> Bool { a.rawValue < b.rawValue }

        /// Portrait, as the glasses deliver it. The link can deliver less; the real size
        /// is on each frame.
        var pixels: (width: Int, height: Int) {
            switch self {
            case .low: return (360, 640)
            case .medium: return (504, 896)
            case .high: return (720, 1280)
            }
        }
    }

    /// Sound from the glasses microphones, carried with the video.
    enum Sound: Int, Comparable, Sendable {
        /// Enough for speech and for recognizing sounds.
        case speech = 16_000
        /// For a recording that is listened to.
        case full = 48_000

        static func < (a: Sound, b: Sound) -> Bool { a.rawValue < b.rawValue }
        var sampleRate: Int { rawValue }
    }

    var resolution: Resolution
    /// One of `StreamPlanner.frameRates`.
    var frameRate: Int
    var sound: Sound?
    /// How many frames a second are turned into images for the phone. The rest are still
    /// handed to a recording, which takes them without that conversion.
    var imagesPerSecond: Double

    /// The stream every build used before profiles existed, and the one a standard build
    /// still uses for everything.
    static let baseline = StreamProfile(resolution: .medium, frameRate: 7, sound: nil, imagesPerSecond: 7)

    /// Whether a stream running with this profile can serve a request for `wanted`
    /// without being restarted.
    func covers(_ wanted: StreamProfile) -> Bool {
        guard resolution >= wanted.resolution, frameRate >= wanted.frameRate else { return false }
        guard let need = wanted.sound else { return true }
        guard let have = sound else { return false }
        return have >= need
    }

    var summary: String {
        let size = resolution.pixels
        let sound = self.sound.map { ", sound at \($0.sampleRate / 1000) kHz" } ?? ""
        return "\(size.width) by \(size.height) at \(frameRate) frames a second\(sound)"
    }
}

enum StreamPlanner {
    /// The only frame rates the toolkit accepts.
    static let frameRates = [2, 7, 15, 24, 30]

    /// The profile for one use. Nil means the glasses are too hot for the camera.
    ///
    /// - Parameters:
    ///   - capabilities: What this build may use, already narrowed by `allowed(in:)`.
    ///   - heat: What the glasses last reported.
    ///   - soundWanted: Whether something is waiting to listen: sound alerts or captions.
    ///     A recording always wants sound.
    static func profile(
        for purpose: StreamPurpose,
        capabilities: GlassesCapabilitySettings,
        heat: GlassesHeat,
        soundWanted: Bool = false
    ) -> StreamProfile? {
        guard heat < .critical else { return nil }
        var profile = capabilities.fullRateVideo ? best(for: purpose) : .baseline
        if capabilities.ambientAudio {
            if purpose == .recording {
                profile.sound = .full
            } else if soundWanted, purpose != .still {
                // One look is over before a sound could be recognized in it.
                profile.sound = .speech
            }
        }
        return cooled(profile, heat: heat, purpose: purpose)
    }

    /// The stream to restart with when a use that may replace the stream finds the camera
    /// already on for something else. Whatever is using the running stream keeps what it
    /// had: the restart only adds. Guide mode does not lose frames because a conversation
    /// about the video began.
    static func replacement(
        for wanted: StreamProfile,
        running: StreamProfile,
        purpose: StreamPurpose,
        heat: GlassesHeat
    ) -> StreamProfile {
        var joined = wanted
        joined.resolution = max(wanted.resolution, running.resolution)
        joined.frameRate = max(wanted.frameRate, running.frameRate)
        joined.imagesPerSecond = max(wanted.imagesPerSecond, running.imagesPerSecond)
        switch (wanted.sound, running.sound) {
        case let (a?, b?): joined.sound = max(a, b)
        case let (a?, nil): joined.sound = a
        case let (nil, b): joined.sound = b
        }
        return cooled(joined, heat: heat, purpose: purpose)
    }

    /// What each use gets when nothing holds it back.
    private static func best(for purpose: StreamPurpose) -> StreamProfile {
        switch purpose {
        case .still:
            // Sharpness matters and motion does not. A slow stream gives each frame more
            // of the link.
            return StreamProfile(resolution: .high, frameRate: 7, sound: nil, imagesPerSecond: 7)
        case .watch:
            return StreamProfile(resolution: .high, frameRate: 7, sound: nil, imagesPerSecond: 2)
        case .guide:
            // The newest frame is at most a 24th of a second old. The detail of the
            // largest size is not needed to see a curb, and costs heat.
            return StreamProfile(resolution: .medium, frameRate: 24, sound: nil, imagesPerSecond: 12)
        case .smartCapture:
            return StreamProfile(resolution: .high, frameRate: 7, sound: nil, imagesPerSecond: 4)
        case .liveVideo:
            return StreamProfile(resolution: .high, frameRate: 15, sound: nil, imagesPerSecond: 15)
        case .lookToTalk:
            // A window's name is small from across a desk, and it does not move. The
            // largest size at a slow rate gives each frame the most of the link.
            return StreamProfile(resolution: .high, frameRate: 7, sound: nil, imagesPerSecond: 2)
        case .recording:
            // The most the toolkit offers. Every frame goes to the file; the phone's
            // preview needs only half of them.
            return StreamProfile(resolution: .high, frameRate: 30, sound: nil, imagesPerSecond: 15)
        }
    }

    private static func cooled(_ profile: StreamProfile, heat: GlassesHeat, purpose: StreamPurpose) -> StreamProfile {
        var cooled = profile
        switch heat {
        case .normal, .light, .critical:
            break
        case .moderate:
            cooled.frameRate = min(cooled.frameRate, 15)
        case .severe:
            cooled.resolution = min(cooled.resolution, .medium)
            cooled.frameRate = min(cooled.frameRate, 7)
            // A recording without sound is not the recording that was asked for. Anything
            // else can do without.
            if purpose != .recording { cooled.sound = nil }
        }
        cooled.imagesPerSecond = min(cooled.imagesPerSecond, Double(cooled.frameRate))
        return cooled
    }
}

/// Lets through at most a set number of frames a second.
struct FrameGate: Sendable {
    private let interval: TimeInterval
    private var last: TimeInterval?

    init(perSecond: Double) {
        // A little under the nominal gap, so a stream whose frames arrive exactly that
        // far apart is not halved by jitter.
        interval = perSecond > 0 ? 0.85 / perSecond : .infinity
    }

    /// `time` is any clock that only moves forward, in seconds.
    mutating func admit(at time: TimeInterval) -> Bool {
        if let last, time >= last, time - last < interval { return false }
        last = time
        return true
    }
}
