// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The switches for what Phoenix Fox asks of the glasses beyond one photo and the
// hands-free microphone.
//
// Each switch names one capability of Meta's Wearables Device Access Toolkit. Meta labels
// five of them beta: they work only for an app in Meta's development or beta release
// channel, and an app that depends on them cannot be published. Those five need the owner
// build as well as their switch. See docs/GLASSES_SDK.md.

import Foundation

struct GlassesCapabilitySettings: Codable, Equatable, Sendable {
    /// Ask for the stream each feature can use best: up to 720 by 1280 at 30 frames a
    /// second for a recording. Off keeps every stream at 504 by 896 and 7 frames a second.
    var fullRateVideo = false

    /// Beta. The touchpad and the action button reach Jarvis while Jarvis is busy with the
    /// wearer: from the wake word until a little after the answer, and for as long as the
    /// camera is on. Outside that time no session is open and the glasses' own gestures
    /// work as usual.
    var controls = false

    /// Beta. In that same time, the capture button takes a look or a picture for Phoenix
    /// Fox, and Meta's own camera does not get the press.
    var captureButton = false

    /// Beta. In that same time, two nods answer yes and a shake answers no to a question
    /// that is waiting.
    var headGestures = false

    /// Beta. Photos from the whole sensor, up to 4032 by 3024, for saved pictures and for
    /// reading text.
    var highResolutionStills = false

    /// Beta. Sound from the glasses microphones arrives with the camera stream, at full
    /// quality and without the filter that keeps only the wearer's voice.
    var ambientAudio = false

    /// Beta. The glasses turn speech into text themselves, as a second ear for the times
    /// the phone's microphone is not listening. Phoenix Fox still acts only on a sentence
    /// that starts with the wake word, and the wake word alone starts the phone listening
    /// again.
    ///
    /// This is the one capability that opens a session when Jarvis is not busy: for as
    /// long as the phone is not listening and the glasses are worn. While any session is
    /// open, the glasses keep a single tap on the touchpad for pausing that session and a
    /// long press for ending it, so in that time those two gestures do not do what they
    /// normally do.
    var onGlassesSpeech = false

    init() {}

    /// Decodes whatever fields are present, so settings saved by an older build still
    /// load and a new field starts at its default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = GlassesCapabilitySettings()
        func value(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? values.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
        }
        fullRateVideo = value(.fullRateVideo, base.fullRateVideo)
        controls = value(.controls, base.controls)
        captureButton = value(.captureButton, base.captureButton)
        headGestures = value(.headGestures, base.headGestures)
        highResolutionStills = value(.highResolutionStills, base.highResolutionStills)
        ambientAudio = value(.ambientAudio, base.ambientAudio)
        onGlassesSpeech = value(.onGlassesSpeech, base.onGlassesSpeech)
    }

    /// What may actually run in this build. The beta capabilities are off outside the
    /// owner build, whatever was saved.
    func allowed(in flavor: BuildFlavor) -> GlassesCapabilitySettings {
        guard !flavor.allowsExperimental else { return self }
        var allowed = GlassesCapabilitySettings()
        allowed.fullRateVideo = fullRateVideo
        return allowed
    }

    /// Whether anything wants a session with the glasses while Jarvis is busy with the
    /// wearer and the camera is off.
    var usesSessionWhileEngaged: Bool { controls || captureButton || headGestures }

    /// Whether anything needs a session while the phone's microphone is not listening.
    var usesSessionWhenPhoneIsDeaf: Bool { onGlassesSpeech }
}

/// What the owner build turns on.
///
/// Turning a feature on makes it available. It does not start the camera, a recording, or
/// a Guide mode walk: those still begin only when the wearer asks, with the capture light
/// on. Two things stay as they were, because they are not the owner's to switch on:
///
/// - The Guide mode safety notice is still read out once and still needs a spoken yes.
/// - Saving a person's face still asks whether that person agreed.
///
/// One capability in the profile changes how the glasses behave when Jarvis is not busy:
/// while the phone is not listening, speech recognized on the glasses keeps a session
/// open, which takes over the touchpad's single tap and long press. See
/// `onGlassesSpeech`. It has its own switch.
enum OwnerProfile {
    /// Raise this when a release adds switches that the owner build should turn on. Each
    /// installed owner build applies the profile once per version, so a switch the owner
    /// turned off afterwards stays off.
    ///
    /// 1: the accessibility suite and the glasses capabilities. 2: the workshop. 3: Look to Talk on.
    static let version = 3

    static func apply(to access: inout AccessibilitySettings) {
        access.faceRecognition = true
        access.soundAlerts = true
        access.keepTranscripts = true
        access.activityRecall = true
        access.guideCloudDescriptions = true
        access.guideAudioCues = true
    }

    static func apply(to glasses: inout GlassesCapabilitySettings) {
        glasses.fullRateVideo = true
        glasses.controls = true
        glasses.captureButton = true
        glasses.headGestures = true
        glasses.highResolutionStills = true
        glasses.ambientAudio = true
        glasses.onGlassesSpeech = true
    }
}
