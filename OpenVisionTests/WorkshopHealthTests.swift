// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class IngredientWatchTests: XCTestCase {
    private func names(_ report: IngredientWatch.Report, _ certainty: IngredientWatch.Certainty) -> [String] {
        report.findings.filter { $0.certainty == certainty }.map(\.name)
    }

    func testAnAllergenIsFoundUnderTheNamesItGoesBy() {
        let label = "INGREDIENTS: Sugar, cocoa butter, whey powder, soya lecithin, natural flavour."
        let report = IngredientWatch.scan(label, watched: ["milk", "soy", "peanuts"])
        XCTAssertEqual(names(report, .listed), ["milk", "soy"])
        XCTAssertEqual(report.findings.first?.evidence, "whey powder")
        XCTAssertTrue(report.sawIngredients)
    }

    func testWordsThatOnlyContainAnAllergenAreNotIt() {
        let label = "Ingredients: cocoa butter, coconut milk, eggplant, nutmeg, buckwheat, water chestnut, cream of tartar."
        let report = IngredientWatch.scan(label, watched: ["milk", "egg", "tree-nuts", "wheat"])
        XCTAssertEqual(report.findings, [])
    }

    func testACommaKeepsTwoIngredientsApart() {
        // "rice milk" and "coconut cream" have no milk in them. "rice, milk" does.
        let report = IngredientWatch.scan("Ingredients: rice, milk, coconut, cream (pasteurised), salt.", watched: ["milk"])
        XCTAssertEqual(names(report, .listed), ["milk"])
        XCTAssertEqual(report.findings.first?.evidence, "milk")
        XCTAssertEqual(IngredientWatch.scan("Ingredients: water, rice milk, coconut cream.", watched: ["milk"]).findings, [])
    }

    func testANewIngredientListEndsAMayContainStatement() {
        // The lines of a label can be read out of order, with no full stop between them.
        let report = IngredientWatch.scan("May contain nuts Ingredients: sugar, milk powder", watched: ["milk", "tree-nuts"])
        XCTAssertEqual(names(report, .listed), ["milk"])
        XCTAssertEqual(names(report, .mayContain), ["tree nuts"])
    }

    func testANutButterIsStillANut() {
        let report = IngredientWatch.scan("Ingredients: peanut butter, almond butter, salt.", watched: ["milk", "peanuts", "tree-nuts"])
        XCTAssertEqual(names(report, .listed), ["tree nuts", "peanuts"])
    }

    func testMayContainIsSaidApartFromListed() {
        let label = """
        Ingredients: wheat flour, sugar, salt
        May contain traces of
        nuts and sesame.
        """
        let report = IngredientWatch.scan(label, watched: ["wheat", "tree-nuts", "sesame", "milk"])
        XCTAssertEqual(names(report, .listed), ["wheat"])
        XCTAssertEqual(names(report, .mayContain), ["tree nuts", "sesame"])
    }

    func testSharedEquipmentCountsAsMayContain() {
        let report = IngredientWatch.scan("Ingredients: oats. Made in a facility that also processes peanuts.", watched: ["peanuts"])
        XCTAssertEqual(names(report, .mayContain), ["peanuts"])
    }

    func testListedWinsWhenALabelSaysBoth() {
        let report = IngredientWatch.scan("May contain milk. Ingredients: milk chocolate.", watched: ["milk"])
        XCTAssertEqual(names(report, .listed), ["milk"])
        XCTAssertEqual(names(report, .mayContain), [])
    }

    func testAFreeFromClaimIsNotAFinding() {
        let report = IngredientWatch.scan("Gluten free. Free from milk, eggs and soy. Ingredients: rice, sugar.", watched: ["gluten", "milk", "egg", "soy"])
        XCTAssertEqual(report.findings, [])
        XCTAssertEqual(report.claims, ["milk", "egg", "gluten", "soy"])
    }

    func testAFreeFromClaimDoesNotHideWhatFollowsIt() {
        // No full stop between the claim and the ingredients, as text recognition often reads it.
        let report = IngredientWatch.scan("Free from artificial colours contains milk and soy", watched: ["milk", "soy"])
        XCTAssertEqual(names(report, .listed), ["milk", "soy"])
    }

    func testFreeRangeIsNotAFreeFromClaim() {
        let report = IngredientWatch.scan("Ingredients: milk, free range eggs, flour", watched: ["milk", "egg"])
        XCTAssertEqual(names(report, .listed), ["milk", "egg"])
    }

    func testAPluralAndAnENumberAreFound() {
        let report = IngredientWatch.scan("Ingredients: almonds, dried apricots (preservative: E220), prawns", watched: ["tree-nuts", "sulfites", "shellfish"])
        XCTAssertEqual(Set(names(report, .listed)), ["tree nuts", "sulfites", "shellfish"])
    }

    func testTheWearersOwnWordsAreMatchedToo() {
        let report = IngredientWatch.scan("Ingredients: strawberry puree, palm oil.", watched: [], custom: ["Palm Oil", "kiwi"])
        XCTAssertEqual(names(report, .listed), ["palm oil"])
    }

    func testTwoReadingsAreJoinedCautiously() {
        let first = IngredientWatch.scan("Ingredients: sugar. May contain milk.", watched: ["milk", "soy"])
        let second = IngredientWatch.scan("Ingredients: sugar, milk powder, soy.", watched: ["milk", "soy"])
        let merged = IngredientWatch.merged(first, second)
        XCTAssertEqual(names(merged, .listed), ["milk", "soy"])
        XCTAssertEqual(names(merged, .mayContain), [])
    }

    func testTheAnswerNeverSaysSafe() {
        let watching = ["milk", "peanuts"]
        let clean = IngredientWatch.scan("Ingredients: rice, sugar, salt, sunflower oil, natural flavour.", watched: ["milk", "peanuts"])
        let hit = IngredientWatch.scan("Ingredients: rice, milk.", watched: ["milk", "peanuts"])
        let nothing = IngredientWatch.scan("Best before", watched: ["milk", "peanuts"])
        for report in [clean, hit, nothing] {
            XCTAssertFalse(IngredientWatch.spoken(report, watching: watching).lowercased().contains("safe"))
        }
        XCTAssertEqual(
            IngredientWatch.spoken(clean, watching: watching),
            "I read 8 words and found none of the words I look for on your list: milk and peanuts. I can misread small print, so check the label before you rely on this."
        )
        XCTAssertEqual(
            IngredientWatch.spoken(hit, watching: watching),
            "Warning. This lists milk. I read: milk. I may have missed other words. Check the label yourself."
        )
    }

    func testTextThatIsNotALabelIsNotReportedAsClear() {
        let report = IngredientWatch.scan("New! Crunchy oat clusters with honey and a hint of vanilla", watched: ["peanuts"])
        XCTAssertEqual(
            IngredientWatch.spoken(report, watching: ["peanuts"]),
            "I could not find an ingredient list. Hold the label closer, in good light, and ask again."
        )
    }

    func testAnEmptyListAsksForOne() {
        let report = IngredientWatch.scan("Ingredients: milk.", watched: [])
        XCTAssertTrue(IngredientWatch.spoken(report, watching: []).hasPrefix("Your ingredient list is empty."))
    }

    func testAllergensAreNamedTheWayPeopleSayThem() {
        XCTAssertEqual(Allergen.named("nuts")?.id, "tree-nuts")
        XCTAssertEqual(Allergen.named("dairy")?.id, "milk")
        XCTAssertEqual(Allergen.named("my peanut allergy")?.id, "peanuts")
        XCTAssertEqual(Allergen.named("Tree nuts")?.id, "tree-nuts")
        XCTAssertNil(Allergen.named("strawberries"))
    }

    func testEveryCatalogTermIsLowercaseWords() {
        for allergen in Allergen.catalog {
            for term in allergen.terms + allergen.innocent {
                XCTAssertEqual(WorkshopText.words(term).joined(separator: " "), term, "\(allergen.id): \(term)")
            }
        }
        XCTAssertEqual(Set(Allergen.catalog.map(\.id)).count, Allergen.catalog.count)
    }
}

final class DoseGuardTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_800_014_400) // 12:00 UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US_POSIX")

    func testTheGapIsReadFromPlainDirections() {
        XCTAssertEqual(DoseGuard.gapHours(inDirections: ["Take 1 tablet every 4-6 hours as needed"]), 4)
        XCTAssertEqual(DoseGuard.gapHours(inDirections: ["Take two caplets every 8 hours"]), 8)
        XCTAssertEqual(DoseGuard.gapHours(inDirections: ["take one tablet every four to six hours"]), 4)
        XCTAssertEqual(DoseGuard.gapHours(inDirections: ["Take one tablet", "once daily with food"]), 20)
        XCTAssertEqual(DoseGuard.gapHours(inDirections: ["Take 1 capsule twice a day"]), 8)
    }

    func testDirectionsThatAreNotPlainGiveNoGap() {
        XCTAssertNil(DoseGuard.gapHours(inDirections: ["Take as directed by your doctor"]))
        XCTAssertNil(DoseGuard.gapHours(inDirections: ["Take every day"]))
        XCTAssertNil(DoseGuard.gapHours(inDirections: ["Take 1 tablet every 400 hours"]))
        XCTAssertNil(DoseGuard.gapHours(inDirections: []))
    }

    func testASecondDoseInsideTheGapIsHeldBack() {
        var log = DoseLog()
        log.log("Ibuprofen Tablets 200 mg", gapHours: 6, source: .label, now: noon)
        let later = noon.addingTimeInterval(40 * 60)
        guard case .tooSoon(let last, let ago, let gap, let fromLabel) = log.check("ibuprofen", gapHours: nil, fallbackHours: 4, now: later) else {
            return XCTFail("expected a warning")
        }
        XCTAssertEqual(last.name, "Ibuprofen Tablets 200 mg")
        XCTAssertEqual(ago, 2_400)
        XCTAssertEqual(gap, 6)
        XCTAssertTrue(fromLabel)
        XCTAssertEqual(
            DoseGuard.spokenTooSoon(last: last, ago: ago, gapHours: gap, fromLabel: fromLabel, calendar: calendar, locale: locale),
            "Wait. You logged Ibuprofen Tablets 200 mg 40 minutes ago, at 12:00 PM. The label says every 6 hours. I have not logged another. If you did take it, say \"log it anyway\"."
        )
        XCTAssertEqual(log.check("ibuprofen", gapHours: nil, fallbackHours: 4, now: noon.addingTimeInterval(6 * 3_600)), .clear)
    }

    func testWithNoLabelGapTheWearersOwnGapIsUsed() {
        var log = DoseLog()
        log.log("vitamin d", gapHours: nil, source: .spoken, now: noon)
        guard case .tooSoon(_, _, let gap, let fromLabel) = log.check("vitamin d", gapHours: nil, fallbackHours: 4, now: noon.addingTimeInterval(3_600)) else {
            return XCTFail("expected a warning")
        }
        XCTAssertEqual(gap, 4)
        XCTAssertFalse(fromLabel)
        XCTAssertEqual(log.check("vitamin d", gapHours: nil, fallbackHours: 4, now: noon.addingTimeInterval(5 * 3_600)), .clear)
    }

    func testADifferentMedicineIsNotHeldBack() {
        var log = DoseLog()
        log.log("Ibuprofen 200 mg", gapHours: 6, source: .label, now: noon)
        XCTAssertEqual(log.check("Acetaminophen 500 mg", gapHours: 4, fallbackHours: 4, now: noon.addingTimeInterval(60)), .clear)
    }

    func testAStrengthOrFormDoesNotMakeItADifferentMedicine() {
        XCTAssertTrue(DoseLog.matches("Ibuprofen Tablets 200 mg", "ibuprofen"))
        XCTAssertTrue(DoseLog.matches("Ibuprofen Tablets 200 mg", "my ibuprofen 400 mg"))
        XCTAssertTrue(DoseLog.matches("ibuprofen", "Advil Ibuprofen Tablets"))
        XCTAssertFalse(DoseLog.matches("Ibuprofen Tablets 200 mg", "tablets"))
        XCTAssertFalse(DoseLog.matches("Ibuprofen", "Acetaminophen"))
        XCTAssertFalse(DoseLog.matches("Ibuprofen", ""))
    }

    func testANameSaidAloudKeepsTheGapItsLabelGave() {
        var log = DoseLog()
        log.log("Ibuprofen 200 mg", gapHours: 6, source: .label, now: noon)
        let second = log.log("ibuprofen", gapHours: nil, source: .spoken, now: noon.addingTimeInterval(7 * 3_600))
        XCTAssertEqual(second.gapHours, 6)
    }

    func testDidITakeIt() {
        var log = DoseLog()
        XCTAssertEqual(DoseGuard.spokenLast(of: "ibuprofen", in: log, now: noon, calendar: calendar, locale: locale), "I have no ibuprofen in the log.")
        log.log("Ibuprofen", gapHours: nil, source: .spoken, now: noon.addingTimeInterval(-3 * 3_600))
        XCTAssertEqual(
            DoseGuard.spokenLast(of: "ibuprofen", in: log, now: noon, calendar: calendar, locale: locale),
            "Yes. Ibuprofen at 9:00 AM, 3 hours ago."
        )
        let tomorrow = noon.addingTimeInterval(20 * 3_600)
        XCTAssertEqual(
            DoseGuard.spokenLast(of: "ibuprofen", in: log, now: tomorrow, calendar: calendar, locale: locale),
            "Not today. The last Ibuprofen I have is yesterday at 9:00 AM, 23 hours ago."
        )
    }

    func testTodayListsOnlyToday() {
        var log = DoseLog()
        log.log("Lisinopril", gapHours: 20, source: .label, now: noon.addingTimeInterval(-26 * 3_600))
        XCTAssertEqual(DoseGuard.spokenToday(log, now: noon, calendar: calendar, locale: locale), "Nothing is logged today.")
        log.log("Lisinopril", gapHours: 20, source: .label, now: noon.addingTimeInterval(-4 * 3_600))
        log.log("Ibuprofen", gapHours: nil, source: .spoken, now: noon)
        XCTAssertEqual(
            DoseGuard.spokenToday(log, now: noon, calendar: calendar, locale: locale),
            "Today: Lisinopril at 8:00 AM and Ibuprofen at 12:00 PM."
        )
        XCTAssertEqual(log.names, ["Ibuprofen", "Lisinopril"])
    }

    func testOldDosesAreDroppedAndUndoRemovesTheLast() {
        var log = DoseLog()
        log.log("Old", gapHours: nil, source: .spoken, now: noon.addingTimeInterval(-91 * 86_400))
        log.log("New", gapHours: nil, source: .spoken, now: noon)
        XCTAssertEqual(log.doses.map(\.name), ["New"])
        XCTAssertEqual(log.removeLast()?.name, "New")
        XCTAssertNil(log.removeLast())
    }

    func testLoggedIsSaidWithTheWayToTakeItBack() {
        var log = DoseLog()
        let dose = log.log("Ibuprofen 200 mg", gapHours: 6, source: .label, now: noon)
        XCTAssertEqual(
            DoseGuard.spokenLogged(dose, calendar: calendar, locale: locale),
            "Logged Ibuprofen 200 mg at 12:00 PM. The label says every 6 hours. Say \"undo that dose\" if this is wrong."
        )
    }

    func testTwoLooksAgreeOnlyOnTheSameWords() {
        XCTAssertEqual(TwoLooks.settle("Ibuprofen 200 mg", "ibuprofen 200mg"), .agreed("Ibuprofen 200 mg"))
        XCTAssertEqual(TwoLooks.settle("Ibuprofen 200 mg", "IBUPROFEN 200 MG."), .agreed("Ibuprofen 200 mg"))
        XCTAssertEqual(TwoLooks.settle("Celebrex", "Celexa"), .disagreed("Celebrex", "Celexa"))
        XCTAssertEqual(TwoLooks.settle("Celebrex", nil), .disagreed("Celebrex", ""))
        XCTAssertEqual(TwoLooks.settle(nil, " "), .unread)
    }
}
