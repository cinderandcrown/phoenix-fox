// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The switches for the workshop: the ten features chosen from docs/INNOVATION_BACKLOG.md.
//
// Every one is off until it is turned on, and none runs outside the owner build. They are
// new, they have not been used on glasses by anyone, and two of them are about medicine
// and allergies. That is not something to hand to a stranger by default.

import Foundation

struct WorkshopSettings: Codable, Equatable, Sendable {
    var walkThrough = false
    var tally = false
    var ingredientWatch = false
    var doseGuard = false
    var council = false
    var relayRace = false
    var standingOrders = false
    var placeNotes = false
    var closeTheDay = false
    var skills = false

    /// The gap Dose guard watches for when a label gives none, in hours.
    var doseGapHours = 4.0
    /// Whether a note is read out, unasked, when the glasses are put on where it was left.
    var offerPlaceNotes = true

    /// Look to Talk: looking at an assistant's window chooses who hears the next request.
    /// Off until the owner profile (or its own switch) turns it on.
    var lookToTalk = false
    /// Lock on as soon as a window is found, so the camera can go off.
    var lookAutoLock = true
    /// Open the microphone after the tone, as the wake word would.
    var lookListenAfterTone = true
    /// How long a lock lasts after it was last used, in minutes.
    var lookLockMinutes = 10.0
    /// Other names an assistant's window may show, such as the handle its chat app uses.
    /// Keyed by the assistant's id, with the names separated by commas.
    var lookOtherNames: [String: String] = [:]

    init() {}

    // A file saved by an earlier build has fewer keys. Anything missing keeps its default.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let base = WorkshopSettings()
        func flag(_ key: CodingKeys, _ fallback: Bool) -> Bool {
            (try? values.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
        }
        walkThrough = flag(.walkThrough, base.walkThrough)
        tally = flag(.tally, base.tally)
        ingredientWatch = flag(.ingredientWatch, base.ingredientWatch)
        doseGuard = flag(.doseGuard, base.doseGuard)
        council = flag(.council, base.council)
        relayRace = flag(.relayRace, base.relayRace)
        standingOrders = flag(.standingOrders, base.standingOrders)
        placeNotes = flag(.placeNotes, base.placeNotes)
        closeTheDay = flag(.closeTheDay, base.closeTheDay)
        skills = flag(.skills, base.skills)
        let gap = (try? values.decodeIfPresent(Double.self, forKey: .doseGapHours)) ?? base.doseGapHours
        doseGapHours = Self.gapRange.contains(gap) ? gap : base.doseGapHours
        offerPlaceNotes = flag(.offerPlaceNotes, base.offerPlaceNotes)
        lookToTalk = flag(.lookToTalk, base.lookToTalk)
        lookAutoLock = flag(.lookAutoLock, base.lookAutoLock)
        lookListenAfterTone = flag(.lookListenAfterTone, base.lookListenAfterTone)
        let minutes = (try? values.decodeIfPresent(Double.self, forKey: .lookLockMinutes)) ?? base.lookLockMinutes
        lookLockMinutes = Self.lockRange.contains(minutes) ? minutes : base.lookLockMinutes
        lookOtherNames = (try? values.decodeIfPresent([String: String].self, forKey: .lookOtherNames)) ?? [:]
    }

    static let gapRange = 1.0...24.0
    static let lockRange = 1.0...60.0

    /// What may actually run in this build: nothing, outside the owner build.
    func allowed(in flavor: BuildFlavor) -> WorkshopSettings {
        guard !flavor.allowsExperimental else { return self }
        var off = WorkshopSettings()
        off.doseGapHours = doseGapHours
        off.offerPlaceNotes = offerPlaceNotes
        off.lookAutoLock = lookAutoLock
        off.lookListenAfterTone = lookListenAfterTone
        off.lookLockMinutes = lookLockMinutes
        off.lookOtherNames = lookOtherNames
        return off
    }

    /// Whether any of the ten is on. Look to Talk is not one of them: it has its own
    /// place in the turn, after these.
    var anyOn: Bool {
        walkThrough || tally || ingredientWatch || doseGuard || council || relayRace
            || standingOrders || placeNotes || closeTheDay || skills
    }

    /// The names each assistant's window may show.
    func lookNames(for bots: [AssistantBot]) -> [LookName] {
        bots.map { bot in
            let others = (lookOtherNames[bot.id] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return LookName(bot: bot.name, others: others)
        }
    }

    /// The tracker's rules, as these settings set them.
    var lookRules: LookTracker.Rules {
        var rules = LookTracker.Rules()
        rules.autoLock = lookAutoLock
        rules.listenAfterTone = lookListenAfterTone
        rules.lockLife = lookLockMinutes * 60
        return rules
    }
}

extension OwnerProfile {
    /// The owner build turns each of the ten workshop features on. What Ingredient watch
    /// looks for is not a setting, and starts empty: only the wearer knows what belongs on
    /// it. Look to Talk is turned on with them.
    static func apply(to workshop: inout WorkshopSettings) {
        workshop.walkThrough = true
        workshop.tally = true
        workshop.ingredientWatch = true
        workshop.doseGuard = true
        workshop.council = true
        workshop.relayRace = true
        workshop.standingOrders = true
        workshop.placeNotes = true
        workshop.closeTheDay = true
        workshop.skills = true
        applyLookToTalk(to: &workshop)
    }

    /// Look to Talk alone, for installations that already had the ten.
    static func applyLookToTalk(to workshop: inout WorkshopSettings) {
        workshop.lookToTalk = true
    }
}
