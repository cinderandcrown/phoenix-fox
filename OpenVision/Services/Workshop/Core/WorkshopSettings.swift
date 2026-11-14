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
    }

    static let gapRange = 1.0...24.0

    /// What may actually run in this build: nothing, outside the owner build.
    func allowed(in flavor: BuildFlavor) -> WorkshopSettings {
        guard !flavor.allowsExperimental else { return self }
        var off = WorkshopSettings()
        off.doseGapHours = doseGapHours
        off.offerPlaceNotes = offerPlaceNotes
        return off
    }

    var anyOn: Bool {
        walkThrough || tally || ingredientWatch || doseGuard || council || relayRace
            || standingOrders || placeNotes || closeTheDay || skills
    }
}

extension OwnerProfile {
    /// The owner build turns every workshop feature on. What Ingredient watch looks for
    /// is not a setting, and starts empty: only the wearer knows what belongs on it.
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
    }
}
