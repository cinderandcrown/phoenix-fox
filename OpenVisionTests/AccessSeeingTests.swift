// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class ReadingOrderTests: XCTestCase {
    private func line(_ text: String, x: Double, y: Double, width: Double = 0.4, height: Double = 0.03) -> TextFragment {
        TextFragment(text, box: FrameBox(x: x, y: y, width: width, height: height))
    }

    func testTwoColumnsAreReadOneAfterTheOther() {
        // The recognizer returns the columns interleaved, row by row.
        let fragments = [
            line("Left one", x: 0.05, y: 0.10), line("Right one", x: 0.55, y: 0.10),
            line("left two", x: 0.05, y: 0.14), line("right two", x: 0.55, y: 0.14),
            line("left three", x: 0.05, y: 0.18), line("right three", x: 0.55, y: 0.18),
        ]
        XCTAssertEqual(ReadingOrder.paragraphs(fragments), ["Left one left two left three", "Right one right two right three"])
    }

    func testAHeadingAcrossBothColumnsIsReadFirst() {
        let fragments = [
            line("right a", x: 0.55, y: 0.14), line("left a", x: 0.05, y: 0.14),
            line("The Daily News", x: 0.05, y: 0.10, width: 0.9),
            line("left b", x: 0.05, y: 0.18), line("right b", x: 0.55, y: 0.18),
        ]
        XCTAssertEqual(ReadingOrder.paragraphs(fragments), ["The Daily News", "left a left b", "right a right b"])
    }

    func testAPriceAtTheEndOfAReceiptRowStaysOnItsRow() {
        let fragments = [
            line("Coffee", x: 0.05, y: 0.10, width: 0.2), line("3.50", x: 0.80, y: 0.10, width: 0.1),
            line("Bagel", x: 0.05, y: 0.14, width: 0.2), line("2.25", x: 0.80, y: 0.14, width: 0.1),
        ]
        // Two rows with a wide gap do form two columns; one row never does.
        XCTAssertEqual(ReadingOrder.lines([fragments[0], fragments[1]]).map(\.text), ["Coffee 3.50"])
    }

    func testAWideGapStartsANewParagraphAndAHyphenIsJoined() {
        let fragments = [
            line("This is an exam-", x: 0.05, y: 0.10), line("ple of wrapping.", x: 0.05, y: 0.14),
            line("A new paragraph.", x: 0.05, y: 0.30),
        ]
        XCTAssertEqual(ReadingOrder.paragraphs(fragments), ["This is an example of wrapping.", "A new paragraph."])
    }

    func testHeadlineKeepsOnlyTheLargeText() {
        let fragments = [
            line("EXIT", x: 0.3, y: 0.2, height: 0.12),
            line("Emergency use only, alarm will sound", x: 0.3, y: 0.4, height: 0.02),
        ]
        XCTAssertEqual(ReadingOrder.headline(fragments), ["EXIT"])
    }

    func testBlankFragmentsAreIgnored() {
        XCTAssertEqual(ReadingOrder.paragraphs([line("  ", x: 0, y: 0)]), [])
        XCTAssertEqual(ReadingOrder.paragraphs([]), [])
    }

    func testALongTextIsReadInPartsAtSentenceEnds() {
        let sentence = "One two three four five six seven eight."
        var session = ReadingSession(paragraphs: [String(repeating: sentence + " ", count: 5)], wordsPerPart: 20)
        XCTAssertTrue(session.spoken.hasPrefix("Part 1 of 3."))
        XCTAssertTrue(session.spoken.hasSuffix("Say read more to continue."))
        XCTAssertFalse(session.goBack())
        XCTAssertTrue(session.advance())
        XCTAssertTrue(session.advance())
        XCTAssertTrue(session.spoken.hasSuffix("That's the end."))
        XCTAssertFalse(session.advance())
        XCTAssertTrue(session.goBack())
        XCTAssertTrue(session.spoken.hasPrefix("Part 2 of 3."))
    }

    func testAShortTextIsReadWhole() {
        let session = ReadingSession(paragraphs: ["Push to open."])
        XCTAssertEqual(session.spoken, "Push to open.")
        XCTAssertFalse(session.hasMore)
    }
}

final class ColorNamerTests: XCTestCase {
    /// Vivid colors sit far from their muted namesakes: a strong blue is nearer to purple
    /// than to a workaday blue unless it has a reference of its own.
    func testVividColorsKeepTheirEverydayNames() {
        XCTAssertEqual(ColorNamer.name(RGB(255, 0, 0)), "red")
        XCTAssertEqual(ColorNamer.name(RGB(0, 0, 255)), "blue")
        XCTAssertEqual(ColorNamer.name(RGB(13, 51, 217)), "blue")
        XCTAssertEqual(ColorNamer.name(RGB(0, 71, 171)), "blue")
        XCTAssertEqual(ColorNamer.name(RGB(30, 144, 255)), "blue")
        XCTAssertEqual(ColorNamer.name(RGB(255, 255, 0)), "yellow")
        XCTAssertEqual(ColorNamer.name(RGB(255, 128, 0)), "orange")
        XCTAssertEqual(ColorNamer.name(RGB(255, 0, 255)), "magenta")
        XCTAssertEqual(ColorNamer.name(RGB(128, 0, 255)), "purple")
        XCTAssertEqual(ColorNamer.name(RGB(100, 40, 140)), "purple")
        XCTAssertEqual(ColorNamer.name(RGB(34, 139, 34)), "green")
    }

    func testEverydayColorsGetTheirNames() {
        XCTAssertEqual(ColorNamer.name(RGB(0, 0, 0)), "black")
        XCTAssertEqual(ColorNamer.name(RGB(255, 255, 255)), "white")
        XCTAssertEqual(ColorNamer.name(RGB(128, 128, 128)), "gray")
        XCTAssertEqual(ColorNamer.name(RGB(210, 25, 30)), "red")
        XCTAssertEqual(ColorNamer.name(RGB(30, 90, 205)), "blue")
        XCTAssertEqual(ColorNamer.name(RGB(245, 225, 55)), "yellow")
        XCTAssertEqual(ColorNamer.name(RGB(35, 145, 65)), "green")
    }

    func testDarkNavyIsNotCalledBlack() {
        // The case that matters for matching clothes: raw RGB distance says black.
        XCTAssertEqual(ColorNamer.name(RGB(24, 34, 80)), "navy blue")
        XCTAssertEqual(ColorNamer.name(RGB(0, 0, 128)), "navy blue")
    }

    func testLabMatchesKnownReferenceValues() {
        let white = Lab(RGB(255, 255, 255))
        XCTAssertEqual(white.l, 100, accuracy: 0.01)
        XCTAssertEqual(white.chroma, 0, accuracy: 0.01)
        let red = Lab(RGB(255, 0, 0))
        XCTAssertEqual(red.l, 53.24, accuracy: 0.05)
        XCTAssertEqual(red.a, 80.09, accuracy: 0.05)
        XCTAssertEqual(red.b, 67.20, accuracy: 0.05)
    }

    func testAStripedPatchNamesBothColors() {
        let samples = Array(repeating: RGB(26, 38, 84), count: 60) + Array(repeating: RGB(250, 250, 250), count: 40)
        let reading = ColorNamer.describe(samples)
        XCTAssertEqual(reading.names, ["navy blue", "white"])
        XCTAssertEqual(reading.spoken, "It looks mostly navy blue, with white.")
    }

    func testAFewStrayPixelsAreNotASecondColor() {
        let samples = Array(repeating: RGB(204, 30, 36), count: 95) + Array(repeating: RGB(250, 250, 250), count: 5)
        XCTAssertEqual(ColorNamer.describe(samples).names, ["red"])
    }

    func testLowLightIsSaid() {
        let reading = ColorNamer.describe(Array(repeating: RGB(12, 10, 14), count: 10))
        XCTAssertTrue(reading.dim)
        XCTAssertTrue(reading.spoken.contains("light is low"))
    }

    func testNoPixelsAsksForACloserLook() {
        XCTAssertTrue(ColorNamer.describe([]).spoken.contains("Hold it closer"))
    }
}

final class CurrencyReaderTests: XCTestCase {
    func testATwentyDollarBill() {
        let texts = ["FEDERAL RESERVE NOTE", "THE UNITED STATES OF AMERICA", "20", "20", "TWENTY DOLLARS", "JB 12345678 A", "SERIES 2017", "20"]
        XCTAssertEqual(CurrencyReader.read(texts), .note(value: 20, currency: "dollar"))
        XCTAssertEqual(CurrencyReader.read(texts).spoken, "20 dollars.")
    }

    func testOneHundredIsNotMistakenForOne() {
        let texts = ["THE UNITED STATES OF AMERICA", "ONE HUNDRED DOLLARS", "100", "100"]
        XCTAssertEqual(CurrencyReader.read(texts), .note(value: 100, currency: "dollar"))
    }

    func testAOneDollarBillIsSingular() {
        let texts = ["FEDERAL RESERVE NOTE", "ONE DOLLAR", "1", "1", "ONE"]
        XCTAssertEqual(CurrencyReader.read(texts).spoken, "1 dollar.")
    }

    func testCornerNumeralsAloneAreEnoughWhenTheyAgree() {
        let texts = ["FEDERAL RESERVE NOTE", "5", "5", "5"]
        XCTAssertEqual(CurrencyReader.read(texts), .note(value: 5, currency: "dollar"))
    }

    func testConflictingValuesAreNotGuessed() {
        // Two bills overlapping in the photo.
        let texts = ["FEDERAL RESERVE NOTE", "10", "10", "20", "20"]
        XCTAssertEqual(CurrencyReader.read(texts), .unsure(currency: "dollar"))
    }

    func testOneGlimpsedNumeralIsNotEnough() {
        XCTAssertEqual(CurrencyReader.read(["THE UNITED STATES OF AMERICA", "50"]), .unsure(currency: "dollar"))
    }

    func testSerialNumbersAndYearsAreNotValues() {
        let texts = ["FEDERAL RESERVE NOTE", "L 10020050 B", "2013", "TEN DOLLARS"]
        XCTAssertEqual(CurrencyReader.read(texts), .note(value: 10, currency: "dollar"))
    }

    func testAPriceTagIsNotMoney() {
        XCTAssertEqual(CurrencyReader.read(["SALE", "20", "DOLLARS OFF"]), .notMoney)
    }

    func testOtherCurrencies() {
        XCTAssertEqual(CurrencyReader.read(["BANK OF ENGLAND", "TEN POUNDS", "10"]), .note(value: 10, currency: "pound"))
        XCTAssertEqual(CurrencyReader.read(["BANK OF CANADA", "BANQUE DU CANADA", "VINGT DOLLARS", "20", "TWENTY DOLLARS"]), .note(value: 20, currency: "Canadian dollar"))
        XCTAssertEqual(CurrencyReader.read(["50", "EURO", "50", "EYPΩ"]).spoken, "50 euros.")
    }
}

final class LabelReaderTests: XCTestCase {
    private func lines(_ texts: [(String, Double)]) -> [TextFragment] {
        texts.enumerated().map { index, pair in
            TextFragment(pair.0, box: FrameBox(x: 0.1, y: Double(index) * 0.05, width: 0.8, height: 0.04), confidence: pair.1)
        }
    }

    func testAPrescriptionIsReadInOrderWithTheAdvice() throws {
        let reading = try XCTUnwrap(LabelReader.medicine(lines([
            ("CITY PHARMACY", 0.99), ("Rx# 1234567", 0.95), ("LISINOPRIL 10 MG TABLETS", 0.97),
            ("Take 1 tablet by mouth daily", 0.96), ("Do not take with potassium supplements", 0.9),
            ("EXP 05/2027", 0.93),
        ])))
        XCTAssertEqual(reading.product, "LISINOPRIL 10 MG TABLETS")
        XCTAssertEqual(reading.directions, ["Take 1 tablet by mouth daily"])
        XCTAssertEqual(reading.warnings, ["Do not take with potassium supplements"])
        XCTAssertEqual(reading.expiry, "EXP 05/2027")
        XCTAssertFalse(reading.doubtful)
        XCTAssertEqual(
            reading.spoken,
            "LISINOPRIL 10 MG TABLETS. Directions: Take 1 tablet by mouth daily. EXP 05/2027. Warnings: Do not take with potassium supplements. " + LabelReader.Reading.advice
        )
    }

    func testAnUnclearStrengthIsNeverSpoken() throws {
        let reading = try XCTUnwrap(LabelReader.medicine(lines([
            ("METFORMIN 500 MG TABLETS", 0.41), ("Take 1 tablet twice daily with food", 0.95), ("Pharmacy refill 2", 0.9),
        ])))
        XCTAssertNil(reading.product)
        XCTAssertTrue(reading.doubtful)
        XCTAssertFalse(reading.spoken.contains("500"))
        XCTAssertTrue(reading.spoken.contains("I can't read the name and strength clearly"))
        XCTAssertTrue(reading.spoken.contains("may be missing"))
    }

    func testAnUnclearDirectionIsLeftOut() throws {
        let reading = try XCTUnwrap(LabelReader.medicine(lines([
            ("IBUPROFEN 200 MG TABLETS", 0.95), ("Take 2 tablets every 6 hours", 0.5),
        ])))
        XCTAssertTrue(reading.directions.isEmpty)
        XCTAssertTrue(reading.doubtful)
    }

    func testAFoodLabelIsNotMedicine() {
        XCTAssertNil(LabelReader.medicine(lines([("TOMATO SOUP", 0.99), ("NET WT 400 g", 0.98), ("Our house recipe", 0.97)])))
    }

    func testStrengthUnits() {
        XCTAssertTrue(LabelReader.hasStrength("amoxicillin 0.5 ml"))
        XCTAssertTrue(LabelReader.hasStrength("hydrocortisone 2.5% cream"))
        XCTAssertTrue(LabelReader.hasStrength("vitamin d 1,000 iu"))
        XCTAssertFalse(LabelReader.hasStrength("20 gauge needle"))
        XCTAssertFalse(LabelReader.hasStrength("rx# 1234567"))
    }
}

final class FaceLedgerTests: XCTestCase {
    func testAClearMatchIsNamed() {
        XCTAssertEqual(FaceLedger.match(distances: [("Sam", 0.31), ("Alex", 0.62)]), .known(name: "Sam"))
    }

    func testNobodyCloseIsAStranger() {
        XCTAssertEqual(FaceLedger.match(distances: [("Sam", 0.58)]), .stranger)
        XCTAssertEqual(FaceLedger.match(distances: []), .stranger)
    }

    func testTwoCloseCandidatesAreNotGuessed() {
        XCTAssertEqual(FaceLedger.match(distances: [("Sam", 0.40), ("Alex", 0.42)]), .unsure)
    }

    func testSpokenAnswers() {
        XCTAssertEqual(FaceLedger.spoken([.known(name: "Sam")]), "This looks like Sam.")
        XCTAssertEqual(FaceLedger.spoken([.known(name: "Sam"), .stranger]), "This looks like Sam. There is one more person I don't recognize.")
        XCTAssertEqual(FaceLedger.spoken([.known(name: "Sam"), .known(name: "Alex"), .known(name: "Jo")]), "This looks like Sam, Alex, and Jo.")
        XCTAssertEqual(FaceLedger.spoken([.stranger]), "I don't recognize this person.")
        XCTAssertTrue(FaceLedger.spoken([.unsure]).contains("I won't guess"))
        XCTAssertTrue(FaceLedger.spoken([]).contains("I don't see a face"))
    }

    func testSavingKeepsTheNewestPrintsAndTheConsentDate() {
        let first = Date(timeIntervalSince1970: 1_000)
        var records = FaceLedger.saving(print: Data([0]), for: "Sam", consentAt: first, in: [])
        for byte in 1...6 {
            records = FaceLedger.saving(print: Data([UInt8(byte)]), for: "sam", consentAt: first.addingTimeInterval(Double(byte)), in: records)
        }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].prints, (2...6).map { Data([UInt8($0)]) })
        XCTAssertEqual(records[0].consentAt, first.addingTimeInterval(6))
    }
}
