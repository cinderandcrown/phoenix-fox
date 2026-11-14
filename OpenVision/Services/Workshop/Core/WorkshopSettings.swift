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

    /// What Ingredient watch looks for: ids from `Allergen.catalog`.
    var allergens: [String] = []
    /// The wearer's own words to look for, as well as the catalog.
    var customIngredients: [String] = []
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
        allergens = (try? values.decodeIfPresent([String].self, forKey: .allergens)) ?? base.allergens
        customIngredients = (try? values.decodeIfPresent([String].self, forKey: .customIngredients)) ?? base.customIngredients
        let gap = (try? values.decodeIfPresent(Double.self, forKey: .doseGapHours)) ?? base.doseGapHours
        doseGapHours = Self.gapRange.contains(gap) ? gap : base.doseGapHours
        offerPlaceNotes = flag(.offerPlaceNotes, base.offerPlaceNotes)
    }

    static let gapRange = 1.0...24.0

    /// What may actually run in this build: nothing, outside the owner build.
    func allowed(in flavor: BuildFlavor) -> WorkshopSettings {
        guard !flavor.allowsExperimental else { return self }
        var off = WorkshopSettings()
        // The lists are kept, so they are still there if the build changes.
        off.allergens = allergens
        off.customIngredients = customIngredients
        off.doseGapHours = doseGapHours
        return off
    }

    var anyOn: Bool {
        walkThrough || tally || ingredientWatch || doseGuard || council || relayRace
            || standingOrders || placeNotes || closeTheDay || skills
    }

    /// The names of what Ingredient watch looks for, as they are said.
    var watchedNames: [String] {
        Allergen.catalog.filter { allergens.contains($0.id) }.map(\.name) + customIngredients
    }

    /// Adds something to watch for. Returns its name as it will be said, or nil when it
    /// was already on the list.
    mutating func watch(_ spoken: String) -> String? {
        if let allergen = Allergen.named(spoken) {
            guard !allergens.contains(allergen.id) else { return nil }
            allergens.append(allergen.id)
            return allergen.name
        }
        let word = WorkshopText.words(spoken).joined(separator: " ")
        guard !word.isEmpty, word.count <= 40, !customIngredients.contains(word), customIngredients.count < 40 else { return nil }
        customIngredients.append(word)
        return word
    }

    /// Stops watching for something. Returns its name, or nil when it was not on the list.
    mutating func unwatch(_ spoken: String) -> String? {
        if let allergen = Allergen.named(spoken), let index = allergens.firstIndex(of: allergen.id) {
            allergens.remove(at: index)
            return allergen.name
        }
        let word = WorkshopText.words(spoken).joined(separator: " ")
        guard let index = customIngredients.firstIndex(of: word) else { return nil }
        customIngredients.remove(at: index)
        return word
    }
}

extension OwnerProfile {
    /// The owner build turns every workshop feature on. The allergen list stays empty:
    /// only the wearer knows what belongs on it.
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
