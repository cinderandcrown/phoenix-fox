// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The accessibility suite's settings.
//
// Features that use the camera on other people, keep a transcript, or listen all the time
// start off, and each is turned on by the wearer in settings or by voice. Features that
// only act when asked, such as reading text or naming a color, need no switch.

import Foundation

struct AccessibilitySettings: Codable, Equatable, Sendable {
    // Seeing
    /// The wearer has heard and accepted that Guide mode is an aid, not a replacement for
    /// a cane or a guide dog.
    var guideSafetyAccepted = false
    /// Guide mode may send a frame to the cloud model when the scene changes. Off keeps
    /// Guide mode to what the phone can detect by itself.
    var guideCloudDescriptions = true
    var guideAudioCues = true
    var faceRecognition = false

    // Getting help
    var emergencyContactName = ""
    var emergencyContactNumber = ""

    // Hearing
    var soundAlerts = false
    var soundKinds: Set<SoundKind> = Set(SoundKind.allCases)
    /// Names and nicknames that raise an alert when heard in live captions.
    var names: [String] = []
    /// Also say sound alerts aloud, for wearers with some hearing.
    var speakSoundAlerts = false
    /// Keep caption lines on this phone after captions stop, so they can be saved.
    var keepTranscripts = false

    // Speech and movement
    var pace: SpeechPace = .normal
    /// Wait longer for the wearer to finish speaking before acting.
    var extraTime = false

    // Memory
    var activityRecall = false

    init() {}

    /// Decodes whatever fields are present, so settings saved by an older build still
    /// load and a new field starts at its default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = AccessibilitySettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        guideSafetyAccepted = value(.guideSafetyAccepted, base.guideSafetyAccepted)
        guideCloudDescriptions = value(.guideCloudDescriptions, base.guideCloudDescriptions)
        guideAudioCues = value(.guideAudioCues, base.guideAudioCues)
        faceRecognition = value(.faceRecognition, base.faceRecognition)
        emergencyContactName = value(.emergencyContactName, base.emergencyContactName)
        emergencyContactNumber = value(.emergencyContactNumber, base.emergencyContactNumber)
        soundAlerts = value(.soundAlerts, base.soundAlerts)
        // Read as plain strings: a kind this build does not know is skipped, not a failure.
        let kinds = (try? values.decodeIfPresent([String].self, forKey: .soundKinds)) ?? nil
        soundKinds = kinds.map { Set($0.compactMap(SoundKind.init(rawValue:))) } ?? base.soundKinds
        names = value(.names, base.names)
        speakSoundAlerts = value(.speakSoundAlerts, base.speakSoundAlerts)
        keepTranscripts = value(.keepTranscripts, base.keepTranscripts)
        pace = value(.pace, base.pace)
        extraTime = value(.extraTime, base.extraTime)
        activityRecall = value(.activityRecall, base.activityRecall)
    }

    /// How much longer than usual to wait for a command to start or continue.
    var patience: Double { extraTime ? 2.5 : 1 }

    /// Extra seconds of quiet allowed inside a sentence before it counts as finished.
    var extraPause: TimeInterval { extraTime ? 2 : 0 }
}

/// The spoken list of what the suite can do, for "what can I say?".
enum AccessHelp {
    static let spoken = """
    Here is what you can say. \
    To see: read this, read the sign, read the label, what bill is this, what color is this, \
    describe the scene, who is this, and start guide mode. \
    To get around: walk me to a place, next turn, where am I, and call my emergency contact. \
    To hear: start captions, what did they say, save this conversation, and turn on sound alerts. \
    For tasks: guide me through something step by step, then next, back, or repeat. \
    You can also say what was I doing, speak slower, or give me more time.
    """
}
