// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class SpokenNumberTests: XCTestCase {
    func testWordsAndDigitsGiveTheSameNumber() {
        XCTAssertEqual(SpokenNumber.value("twelve"), 12)
        XCTAssertEqual(SpokenNumber.value("12"), 12)
        XCTAssertEqual(SpokenNumber.value("twenty three"), 23)
        XCTAssertEqual(SpokenNumber.value("one hundred and five"), 105)
        XCTAssertEqual(SpokenNumber.value("a hundred"), 100)
        XCTAssertEqual(SpokenNumber.value("twelve hundred"), 1_200)
        XCTAssertEqual(SpokenNumber.value("two thousand three hundred forty one"), 2_341)
        XCTAssertEqual(SpokenNumber.value("1,200"), 1_200)
        XCTAssertEqual(SpokenNumber.value("zero"), 0)
    }

    func testDozensAndCouples() {
        XCTAssertEqual(SpokenNumber.value("a dozen"), 12)
        XCTAssertEqual(SpokenNumber.value("two dozen"), 24)
        XCTAssertEqual(SpokenNumber.value("3 dozen"), 36)
        XCTAssertEqual(SpokenNumber.leading(["a", "couple", "of", "lids"])?.value, 2)
        XCTAssertEqual(SpokenNumber.leading(["a", "couple", "of", "lids"])?.used, 3)
    }

    func testANumberStopsWhereTheWordsStopBeingOne() {
        let found = SpokenNumber.leading(["twenty", "five", "cases", "of", "cups"])
        XCTAssertEqual(found?.value, 25)
        XCTAssertEqual(found?.used, 2)
        // Two numbers side by side are two numbers, not one.
        XCTAssertEqual(SpokenNumber.leading(["two", "three"])?.value, 2)
        XCTAssertEqual(SpokenNumber.leading(["ten", "five"])?.value, 10)
        XCTAssertNil(SpokenNumber.value("two three"))
    }

    func testAnArticleCountsOnlyWhenAsked() {
        XCTAssertNil(SpokenNumber.leading(["a", "box"]))
        XCTAssertEqual(SpokenNumber.leading(["a", "box"], articles: true)?.value, 1)
        XCTAssertEqual(SpokenNumber.leading(["an", "apple"], articles: true)?.value, 1)
    }

    func testWordsThatAreNotNumbersAreRefused() {
        XCTAssertNil(SpokenNumber.value("cups"))
        XCTAssertNil(SpokenNumber.value(""))
        XCTAssertNil(SpokenNumber.value("and"))
        XCTAssertNil(SpokenNumber.value("hundred"))
        // Past the limit a count is more likely a mishearing.
        XCTAssertNil(SpokenNumber.value("12000"))
        XCTAssertNil(SpokenNumber.value("nine thousand nine hundred ninety nine dozen"))
    }
}

final class SaidTests: XCTestCase {
    func testTheWakeWordAndPolitenessAreDropped() {
        XCTAssertEqual(Said("Hey Phoenix, please start a tally.").text, "start a tally")
        XCTAssertEqual(Said("Phoenix, can you check the ingredients please?").text, "check the ingredients")
        XCTAssertEqual(Said("Phoenix").text, "phoenix")
    }

    func testWhatFollowsACommandKeepsItsCapitals() {
        let said = Said("Phoenix, note Dana wants the Elm Street permit by Friday")
        XCTAssertEqual(said.after(["note"]), "Dana wants the Elm Street permit by Friday")
        XCTAssertEqual(said.after(["flag"]), nil)
        XCTAssertEqual(Said("note").after(["note"]), "")
    }

    func testALeadMustEndOnAWord() {
        XCTAssertNil(Said("notebook is on the desk").after(["note"]))
    }

    func testSpansAreSaidTheWayAPersonWould() {
        XCTAssertEqual(WorkshopText.span(20), "less than a minute")
        XCTAssertEqual(WorkshopText.span(40 * 60), "40 minutes")
        XCTAssertEqual(WorkshopText.span(80 * 60), "1 hour 20 minutes")
        XCTAssertEqual(WorkshopText.span(2 * 3_600), "2 hours")
        XCTAssertEqual(WorkshopText.span(7 * 3_600 + 600), "7 hours")
        XCTAssertEqual(WorkshopText.span(3 * 86_400), "3 days")
    }

    func testLists() {
        XCTAssertEqual(WorkshopText.list([]), "")
        XCTAssertEqual(WorkshopText.list(["milk"]), "milk")
        XCTAssertEqual(WorkshopText.list(["milk", "egg"]), "milk and egg")
        XCTAssertEqual(WorkshopText.list(["milk", "egg", "soy"]), "milk, egg, and soy")
    }
}

final class TallyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheSameItemSaidTwoWaysIsOneLine() {
        var tally = Tally(name: "stockroom", startedAt: start)
        tally.add(12, of: "cases of cups")
        let line = tally.add(1, of: "case of cups")
        XCTAssertEqual(line, Tally.Line(item: "cases of cups", count: 13))
        XCTAssertEqual(tally.lines.count, 1)
        tally.add(3, of: "the boxes")
        tally.add(2, of: "box")
        XCTAssertEqual(tally.count(of: "boxes")?.count, 5)
        XCTAssertEqual(tally.total, 18)
    }

    func testPluralsAreMatchedWithoutManglingOtherWords() {
        XCTAssertEqual(Tally.key("batteries"), Tally.key("battery"))
        XCTAssertEqual(Tally.key("glasses"), Tally.key("glass"))
        XCTAssertEqual(Tally.key("boxes of lids"), Tally.key("box of lid"))
        XCTAssertNotEqual(Tally.key("cups"), Tally.key("caps"))
        // Short words and words that only look plural are left alone.
        XCTAssertEqual(Tally.key("gas"), "gas")
        XCTAssertEqual(Tally.key("bus"), "bus")
    }

    func testACountNeverGoesBelowZero() {
        var tally = Tally(name: "bar", startedAt: start)
        tally.add(2, of: "lids")
        XCTAssertEqual(tally.add(-5, of: "lids")?.count, 0)
    }

    func testUndoTakesBackOneChangeAtATime() {
        var tally = Tally(name: "bar", startedAt: start)
        tally.add(40, of: "lids")
        tally.add(4, of: "lids")
        tally.add(6, of: "straws")
        XCTAssertEqual(tally.undo()?.item, "straws")
        XCTAssertNil(tally.count(of: "straws"))
        XCTAssertEqual(tally.undo()?.before, 40)
        XCTAssertEqual(tally.count(of: "lids")?.count, 40)
        XCTAssertNotNil(tally.undo())
        XCTAssertTrue(tally.isEmpty)
        XCTAssertNil(tally.undo())
    }

    func testSetReplacesACount() {
        var tally = Tally(name: "bar", startedAt: start)
        tally.add(40, of: "lids")
        XCTAssertEqual(tally.set(35, of: "lid")?.count, 35)
        XCTAssertEqual(tally.undo()?.after, 35)
        XCTAssertEqual(tally.count(of: "lids")?.count, 40)
    }

    func testTheSummarySaysEachItemAndTheTotals() {
        var tally = Tally(name: "bar", startedAt: start)
        XCTAssertEqual(tally.spokenSummary(), "The bar tally is empty.")
        tally.add(12, of: "cups")
        tally.add(40, of: "lids")
        XCTAssertEqual(tally.spokenSummary(), "Cups, 12. Lids, 40. 2 items, 52 in all.")
        XCTAssertEqual(tally.spokenSummary(limit: 1), "Cups, 12. And 1 more item. 2 items, 52 in all.")
    }

    func testTheSheetQuotesWhatASpreadsheetWouldMisread() {
        var tally = Tally(name: "bar", startedAt: start)
        tally.add(2, of: "cups, large")
        tally.add(1, of: "=cmd")
        XCTAssertEqual(tally.csv(), "item,count\n\"cups, large\",2\n'=cmd,1\ntotal,3")
    }

    func testATallySurvivesBeingSaved() throws {
        var tally = Tally(name: "bar", startedAt: start)
        tally.add(12, of: "cups")
        let copy = try JSONDecoder().decode(Tally.self, from: JSONEncoder().encode(tally))
        XCTAssertEqual(copy, tally)
    }
}

final class WalkThroughTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let locale = Locale(identifier: "en_US_POSIX")

    private func sample() -> WalkThrough {
        var walk = WalkThrough(name: "Elm Street house", startedAt: start)
        walk.add(.note, "kitchen tile is finished", at: start.addingTimeInterval(60))
        walk.add(.flag, "outlet by the sink has no cover", photo: "p1", at: start.addingTimeInterval(120))
        walk.add(.note, "", photo: "p2", at: start.addingTimeInterval(180))
        walk.finishedAt = start.addingTimeInterval(600)
        return walk
    }

    func testItemsAreAcknowledgedByNumberAndKind() {
        var walk = WalkThrough(name: "site", startedAt: start)
        let note = walk.add(.note, "door sticks", at: start)!
        XCTAssertEqual(walk.spokenAck(for: note), "Note 1.")
        XCTAssertEqual(note.text, "Door sticks")
        let flag = walk.add(.flag, "", photo: "p", at: start)!
        XCTAssertEqual(walk.spokenAck(for: flag), "Flag 2, with a photo.")
        XCTAssertEqual(flag.text, "Photo")
        XCTAssertEqual(walk.add(.flag, " ", at: start)?.text, "No description")
    }

    func testFlagsLeadTheSummaryAndTheReport() {
        let walk = sample()
        XCTAssertEqual(walk.spokenCounts, "3 items, 1 flag, and 2 photos")
        XCTAssertTrue(walk.spokenSummary().hasPrefix("Elm Street house: 3 items, 1 flag, and 2 photos. Flag: Outlet by the sink has no cover."))

        let report = walk.report(calendar: calendar, locale: locale)
        let lines = report.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "# Walk-through: Elm Street house")
        let attention = lines.firstIndex(of: "## Needs attention")!
        let notes = lines.firstIndex(of: "## Notes")!
        XCTAssertLessThan(attention, notes)
        XCTAssertTrue(lines[attention + 1].hasSuffix("Outlet by the sink has no cover. (photo 1)"))
        // Photo numbers follow the order the pictures are sent in, not the order of the report.
        XCTAssertTrue(lines.last!.hasSuffix("Photo. (photo 2)"))
    }

    func testPhotosAreNumberedInTheOrderTheyAreSentFlagsFirst() {
        var walk = WalkThrough(name: "site", startedAt: start)
        walk.add(.note, "first picture", photo: "a", at: start)
        walk.add(.flag, "second picture", photo: "b", at: start)
        walk.add(.note, "third picture", photo: "c", at: start)
        let sent = walk.photosToSend(limit: 2)
        XCTAssertEqual(sent.compactMap(\.photo), ["b", "a"])
        let report = walk.report(sent: sent, calendar: calendar, locale: locale)
        XCTAssertTrue(report.contains("Second picture. (photo 1)"))
        XCTAssertTrue(report.contains("First picture. (photo 2)"))
        XCTAssertTrue(report.contains("Third picture. (photo kept on the phone)"))
    }

    func testAReportThatIsTooLongSaysHowMuchWasLeftOut() {
        var walk = WalkThrough(name: "warehouse", startedAt: start)
        for index in 1...120 {
            walk.add(.note, "Bay \(index) racking checked and the load signs are in place", at: start)
        }
        let report = walk.report(calendar: calendar, locale: locale, limit: 2_000)
        XCTAssertLessThanOrEqual(report.count, 2_000)
        let kept = report.split(separator: "\n").filter { $0.hasPrefix("- ") }.count
        XCTAssertTrue(report.hasSuffix("\(120 - kept) more items did not fit in this message."))
        XCTAssertGreaterThan(kept, 10)
    }

    func testAWalkThroughStopsTakingItemsWhenFull() {
        var walk = WalkThrough(name: "site", startedAt: start)
        for _ in 0..<WalkThrough.itemLimit { XCTAssertNotNil(walk.add(.note, "x", at: start)) }
        XCTAssertNil(walk.add(.note, "one too many", at: start))
        XCTAssertEqual(walk.removeLast()?.text, "X")
        XCTAssertNotNil(walk.add(.note, "fits again", at: start))
    }

    func testAnEmptyWalkThroughSaysSo() {
        let walk = WalkThrough(name: "site", startedAt: start)
        XCTAssertEqual(walk.spokenSummary(), "The site walk-through has nothing in it yet.")
        XCTAssertEqual(walk.spokenCounts, "nothing noted")
    }
}
