// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Decides when a sound the phone heard is worth interrupting a Deaf or hard-of-hearing
// wearer for.
//
// The system sound classifier reports a guess about every second, and most guesses are
// wrong for a moment: a spoon on a cup scores as a doorbell. An alert fires only when the
// same kind of sound holds above its threshold across consecutive windows, and then it
// waits before firing for that kind again, so one siren is one alert and not twenty.

import Foundation

enum SoundKind: String, Codable, CaseIterable, Sendable {
    case siren, smokeAlarm, doorbell, knock, carHorn, babyCrying, dogBark, phoneRinging
    case alarmClock, glassBreaking, shouting, applianceBeep, waterRunning

    /// What is shown and, when the wearer wants it, said.
    var message: String {
        switch self {
        case .siren: return "Siren nearby"
        case .smokeAlarm: return "Smoke alarm"
        case .doorbell: return "Doorbell"
        case .knock: return "Knocking"
        case .carHorn: return "Car horn"
        case .babyCrying: return "Baby crying"
        case .dogBark: return "Dog barking"
        case .phoneRinging: return "Phone ringing"
        case .alarmClock: return "Alarm ringing"
        case .glassBreaking: return "Glass breaking"
        case .shouting: return "Someone shouting"
        case .applianceBeep: return "Appliance beeping"
        case .waterRunning: return "Water running"
        }
    }

    /// The name shown beside the switch in settings.
    var title: String {
        switch self {
        case .siren: return "Sirens"
        case .smokeAlarm: return "Smoke and fire alarms"
        case .doorbell: return "Doorbell"
        case .knock: return "Door knock"
        case .carHorn: return "Car horns"
        case .babyCrying: return "Baby crying"
        case .dogBark: return "Dog barking"
        case .phoneRinging: return "Phone ringing"
        case .alarmClock: return "Alarm clocks and timers"
        case .glassBreaking: return "Glass breaking"
        case .shouting: return "Shouting or screaming"
        case .applianceBeep: return "Appliance beeps"
        case .waterRunning: return "Water running"
        }
    }

    /// Danger to life or safety. These use a lower threshold and a shorter wait.
    var urgent: Bool {
        switch self {
        case .siren, .smokeAlarm, .carHorn, .glassBreaking, .shouting: return true
        default: return false
        }
    }

    /// Words found in the classifier's labels for this kind. Labels are matched by these
    /// words and not by exact name, so a label added or renamed in a later system release
    /// still lands on the right kind.
    fileprivate var words: [String] {
        switch self {
        case .siren: return ["siren", "emergency_vehicle"]
        case .smokeAlarm: return ["smoke", "fire_alarm"]
        case .doorbell: return ["door_bell", "doorbell"]
        case .knock: return ["knock"]
        case .carHorn: return ["car_horn", "air_horn", "truck_horn", "vehicle_horn"]
        case .babyCrying: return ["baby_cry", "infant_cry"]
        case .dogBark: return ["dog_bark", "dog_bow_wow", "dog_growl"]
        case .phoneRinging: return ["telephone", "ringtone"]
        case .alarmClock: return ["alarm_clock", "timer"]
        case .glassBreaking: return ["glass_break", "shatter"]
        case .shouting: return ["scream", "shout", "yell"]
        case .applianceBeep: return ["beep", "microwave"]
        case .waterRunning: return ["water_tap", "faucet", "sink_filling", "bathtub_filling"]
        }
    }

    /// The kind a classifier label belongs to, if any.
    static func matching(_ label: String) -> SoundKind? {
        let lower = label.lowercased()
        return allCases.first { kind in kind.words.contains { lower.contains($0) } }
    }

    /// The kinds this device's classifier can actually report, given every label it knows.
    static func supported(byLabels labels: [String]) -> Set<SoundKind> {
        Set(labels.compactMap(matching))
    }
}

struct SoundAlert: Equatable, Sendable {
    var kind: SoundKind
    var confidence: Double
    var at: Date
}

struct SoundAlertPolicy: Sendable {
    var enabled: Set<SoundKind>
    /// Windows in a row a sound must hold before it counts.
    var windowsNeeded = 2

    private var streak: [SoundKind: Int] = [:]
    private var lastFired: [SoundKind: Date] = [:]

    init(enabled: Set<SoundKind> = Set(SoundKind.allCases)) {
        self.enabled = enabled
    }

    /// Takes one window of classifier output and returns the alerts to raise now.
    ///
    /// - Parameter scores: Every label the classifier scored for this window, with its
    ///   confidence from 0 to 1.
    mutating func observe(_ scores: [(label: String, confidence: Double)], at now: Date) -> [SoundAlert] {
        var best: [SoundKind: Double] = [:]
        for score in scores {
            guard let kind = SoundKind.matching(score.label), enabled.contains(kind) else { continue }
            best[kind] = max(best[kind] ?? 0, score.confidence)
        }
        var alerts: [SoundAlert] = []
        for kind in SoundKind.allCases where enabled.contains(kind) {
            let confidence = best[kind] ?? 0
            guard confidence >= (kind.urgent ? 0.5 : 0.65) else {
                streak[kind] = 0
                continue
            }
            streak[kind, default: 0] += 1
            guard streak[kind, default: 0] >= windowsNeeded else { continue }
            let wait: TimeInterval = kind.urgent ? 12 : 30
            if let last = lastFired[kind], now.timeIntervalSince(last) < wait { continue }
            lastFired[kind] = now
            alerts.append(SoundAlert(kind: kind, confidence: confidence, at: now))
        }
        return alerts.sorted { ($0.kind.urgent ? 0 : 1, -$0.confidence) < ($1.kind.urgent ? 0 : 1, -$1.confidence) }
    }
}

/// Notices the wearer's name in what was just captioned.
struct NameCallDetector: Sendable {
    private let names: [String]
    private var lastFired: Date?
    private var seenWords = 0

    /// - Parameter names: The names and nicknames to listen for.
    init(names: [String]) {
        self.names = names
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
    }

    /// Call with the caption line as it grows. Returns the name that was heard, once per
    /// time it is said: only words that are new since the last call are checked.
    mutating func heard(_ line: String, at now: Date) -> String? {
        let words = line.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
        // A shorter line than last time means the recognizer started a new one.
        if words.count < seenWords { seenWords = 0 }
        let fresh = Array(words[min(seenWords, words.count)...])
        // Keep one word of overlap, so a two-word name split across updates still matches.
        seenWords = max(0, words.count - 1)
        guard !fresh.isEmpty else { return nil }
        let text = " " + fresh.joined(separator: " ") + " "
        guard let name = names.first(where: { text.contains(" \($0) ") }) else { return nil }
        if let lastFired, now.timeIntervalSince(lastFired) < 10 { return nil }
        lastFired = now
        seenWords = words.count
        return name
    }
}
