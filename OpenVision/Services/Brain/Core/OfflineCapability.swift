// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// On-device first: what still works with no network, and when the cloud is allowed.
//
// Every capability defaults to the phone's Neural Engine and the glasses' own hardware.
// The cloud is used only when on-device quality is clearly worse, or the task needs it
// (deep reasoning, rich vision Q&A, bot actions on a relay). These rules are plain data
// so the capability matrix and the tests share one source of truth.

import Foundation

/// Where a capability runs.
enum RunPlace: String, Equatable, Sendable {
    case onDevice
    case cloud
    case either
}

/// One row of the capability matrix.
struct CapabilityRow: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var place: RunPlace
    /// Works with no internet and no relay.
    var offline: Bool
    /// Hardware or API this relies on. Only names APIs that are actually called.
    var uses: String
    /// When the cloud may be used instead.
    var cloudWhen: String
}

enum CapabilityMatrix {
    /// The product rule: on-device first. Cloud only when needed.
    static let principle = "Default every capability to on-device (phone Neural Engine and glasses hardware). Use the cloud only when on-device quality is clearly worse, or the task needs deep reasoning, rich vision Q&A, or a bot action."

    static let rows: [CapabilityRow] = [
        CapabilityRow(id: "wake", name: "Wake word", place: .onDevice, offline: true,
                      uses: "SFSpeechRecognizer (on-device when preferred)", cloudWhen: "Never for wake."),
        CapabilityRow(id: "stt", name: "Speech to text", place: .onDevice, offline: true,
                      uses: "SFSpeechRecognizer; WhisperKit after wake for assistants", cloudWhen: "Never sent to a paid STT API."),
        CapabilityRow(id: "tts", name: "Text to speech", place: .either, offline: true,
                      uses: "AVSpeechSynthesizer; optional Kokoro/cloud voices when configured", cloudWhen: "Only when a cloud/neural voice is chosen in Settings."),
        CapabilityRow(id: "ocr", name: "Read aloud / OCR", place: .onDevice, offline: true,
                      uses: "Vision VNRecognizeTextRequest", cloudWhen: "Never for plain reading."),
        CapabilityRow(id: "scene", name: "Object / scene ID", place: .either, offline: true,
                      uses: "Vision VNClassifyImageRequest, VNDetectHumanRectanglesRequest, VNRecognizeAnimalsRequest", cloudWhen: "Rich vision Q&A when OCR/labels are not enough."),
        CapabilityRow(id: "face", name: "Face detect / remember", place: .onDevice, offline: true,
                      uses: "Vision face prints on this phone", cloudWhen: "Never; prints stay on device."),
        CapabilityRow(id: "barcode", name: "Barcode / QR", place: .onDevice, offline: true,
                      uses: "Vision VNDetectBarcodesRequest", cloudWhen: "Never."),
        CapabilityRow(id: "sound", name: "Sound alerts (Deaf / HoH)", place: .onDevice, offline: true,
                      uses: "SoundAnalysis on the active mic", cloudWhen: "Never."),
        CapabilityRow(id: "short", name: "Short local replies", place: .either, offline: true,
                      uses: "Apple Intelligence Foundation Models when available; else short templates / local Gemma", cloudWhen: "When Foundation Models unavailable and a cloud key is set."),
        CapabilityRow(id: "timers", name: "Timers / alarms / notes", place: .onDevice, offline: true,
                      uses: "On-phone timers, reminders, local notes", cloudWhen: "Never required."),
        CapabilityRow(id: "memory", name: "Local memory (Mind meld)", place: .onDevice, offline: true,
                      uses: "On-phone episode store", cloudWhen: "Never; nothing leaves without asking."),
        CapabilityRow(id: "motion", name: "Head gestures / motion", place: .onDevice, offline: true,
                      uses: "DAT MWDATMotion / MWDATInputs when enabled", cloudWhen: "Never."),
        CapabilityRow(id: "glasses-mic", name: "Glasses microphone", place: .onDevice, offline: true,
                      uses: "Bluetooth HFP route; DAT PCM while camera runs when ambientAudio is on", cloudWhen: "Never."),
        CapabilityRow(id: "glasses-speaker", name: "Glasses speakers", place: .onDevice, offline: true,
                      uses: "Bluetooth HFP/A2DP output via AVAudioSession", cloudWhen: "Never."),
        CapabilityRow(id: "camera", name: "Glasses camera", place: .onDevice, offline: true,
                      uses: "DAT Camera stream / photo; capture light is hardware", cloudWhen: "Frames leave only for a look that needs rich vision."),
        CapabilityRow(id: "reason", name: "Deep reasoning", place: .cloud, offline: false,
                      uses: "Grok / Claude / OpenAI top model", cloudWhen: "Always when the turn needs the top model."),
        CapabilityRow(id: "vision-qa", name: "Rich vision Q&A", place: .either, offline: true,
                      uses: "On-device SmolVLM2 when loaded; else cloud vision", cloudWhen: "When no on-device vision model and OCR/labels are not enough."),
        CapabilityRow(id: "bots", name: "Bot team actions", place: .cloud, offline: false,
                      uses: "Relay /ask to the wearer's assistants", cloudWhen: "Always; needs the relay."),
    ]

    static var offlineRows: [CapabilityRow] { rows.filter(\.offline) }
    static var cloudOnlyRows: [CapabilityRow] { rows.filter { !$0.offline } }

    /// What to say when a cloud-only action is asked for while offline.
    static func offlineRefusal(for id: String) -> String {
        switch id {
        case "bots":
            return "Your assistants need a connection. I can still listen, read what you see, and take notes on this phone."
        case "reason":
            return "I need a connection for that kind of thinking. Ask me to read something, set a timer, or take a note meanwhile."
        default:
            return "That needs a connection. Wake word, reading, sound alerts, and notes still work offline."
        }
    }
}

/// Whether the phone currently has a path to the internet.
enum NetworkPathStatus: String, Equatable, Sendable {
    case online
    case offline

    var title: String {
        switch self {
        case .online: return "Online"
        case .offline: return "Offline mode"
        }
    }

    var spoken: String {
        switch self {
        case .online: return "Online. Cloud brains are available when configured."
        case .offline: return "Offline mode. Wake word, speech, reading, sound alerts, timers, and notes still work on this phone."
        }
    }
}

/// Pure helpers for offline routing decisions.
enum OfflineGate {
    /// Cloud may be used for this capability only when online (or the capability is on-device).
    static func mayUseCloud(rowId: String, path: NetworkPathStatus) -> Bool {
        guard path == .online else {
            return CapabilityMatrix.rows.first { $0.id == rowId }?.place == .onDevice
        }
        return true
    }

    static func shouldPreferOnDevice(kind: LookKind, path: NetworkPathStatus) -> Bool {
        if path == .offline { return true }
        switch kind {
        case .readText, .code, .who: return true
        case .describeScene: return true // try on-device labels / local VLM first
        }
    }
}
