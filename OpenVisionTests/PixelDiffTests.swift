// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest

final class PixelDiffTests: XCTestCase {
    private func gray(_ value: UInt8, width: Int = 20, height: Int = 25) -> PixelImage {
        PixelImage(width: width, height: height, red: value, green: value, blue: value)
    }

    // MARK: - Pictures

    func testAPictureNeedsFourBytesForEveryPixel() {
        XCTAssertNotNil(PixelImage(width: 2, height: 2, rgba: Array(repeating: 0, count: 16)))
        XCTAssertNil(PixelImage(width: 2, height: 2, rgba: Array(repeating: 0, count: 15)))
        XCTAssertNil(PixelImage(width: 0, height: 2, rgba: []))
    }

    func testAPixelCanBeReadAndWritten() {
        var image = gray(10, width: 3, height: 2)
        image[2, 1] = [1, 2, 3, 4]
        XCTAssertEqual(image[2, 1], [1, 2, 3, 4])
        XCTAssertEqual(image[1, 1], [10, 10, 10, 255])
        XCTAssertEqual(image.rgba.count, 24)
    }

    // MARK: - Comparing

    func testAPictureMatchesItself() {
        let verdict = PixelDiff.compare(reference: gray(120), actual: gray(120))
        XCTAssertEqual(verdict, .same(.init(total: 500, differing: 0, largestDelta: 0)))
        XCTAssertTrue(verdict.passes)
        XCTAssertEqual(verdict.summary, "The picture matches its reference exactly.")
    }

    func testASmallShiftInEveryPixelIsWithinTolerance() {
        let verdict = PixelDiff.compare(reference: gray(120), actual: gray(120 + UInt8(PixelDiff.channelTolerance)))
        XCTAssertEqual(verdict, .same(.init(total: 500, differing: 0, largestDelta: PixelDiff.channelTolerance)))
    }

    func testAShiftJustPastToleranceInEveryPixelFails() {
        let verdict = PixelDiff.compare(reference: gray(120), actual: gray(121 + UInt8(PixelDiff.channelTolerance)))
        XCTAssertFalse(verdict.passes)
        guard case .different(let report) = verdict else { return XCTFail("Expected a difference.") }
        XCTAssertEqual(report.differing, 500)
        XCTAssertEqual(report.fraction, 1)
    }

    func testOnePixelInFiveHundredMayChange() {
        var actual = gray(120)
        actual[3, 4] = [255, 0, 0, 255]
        let verdict = PixelDiff.compare(reference: gray(120), actual: actual)
        XCTAssertTrue(verdict.passes)
        XCTAssertEqual(verdict.summary, "The picture matches its reference. 1 of 500 pixels are slightly off, within tolerance.")
    }

    func testTwoPixelsInFiveHundredMayNot() {
        var actual = gray(120)
        actual[3, 4] = [255, 0, 0, 255]
        actual[4, 4] = [255, 0, 0, 255]
        let verdict = PixelDiff.compare(reference: gray(120), actual: actual)
        XCTAssertFalse(verdict.passes)
        XCTAssertEqual(
            verdict.summary,
            "The picture differs from its reference in 2 of 500 pixels (0.4%). The largest difference in a channel is 135 of 255."
        )
    }

    func testAChangeInAlphaAloneCounts() {
        var actual = gray(120, width: 2, height: 2)
        actual[0, 0] = [120, 120, 120, 0]
        let verdict = PixelDiff.compare(reference: gray(120, width: 2, height: 2), actual: actual)
        XCTAssertFalse(verdict.passes)
    }

    func testADifferentSizeIsItsOwnVerdict() {
        let verdict = PixelDiff.compare(reference: gray(120), actual: gray(120, width: 20, height: 30))
        XCTAssertEqual(verdict, .sizeChanged(reference: "20 by 25", actual: "20 by 30"))
        XCTAssertEqual(verdict.summary, "The picture is 20 by 30 and its reference is 20 by 25.")
        XCTAssertFalse(verdict.passes)
    }

    func testTheToleranceCanBeTightened() {
        let verdict = PixelDiff.compare(reference: gray(120), actual: gray(121), channelTolerance: 0, allowedFraction: 0)
        XCTAssertFalse(verdict.passes)
    }

    // MARK: - Blank pictures

    func testOneColorEverywhereIsBlank() {
        XCTAssertTrue(PixelDiff.isBlank(gray(0)))
        XCTAssertTrue(PixelDiff.isBlank(gray(255)))
    }

    func testOneDifferentPixelIsNotBlank() {
        var image = gray(0)
        image[19, 24] = [0, 0, 1, 255]
        XCTAssertFalse(PixelDiff.isBlank(image))
    }

    // MARK: - Marking what changed

    func testChangedPixelsAreMarkedAndTheRestFaded() throws {
        var actual = gray(90, width: 4, height: 4)
        actual[1, 2] = [0, 0, 0, 255]
        let marked = try XCTUnwrap(PixelDiff.marked(reference: gray(90, width: 4, height: 4), actual: actual))
        XCTAssertEqual(marked[1, 2], [255, 0, 255, 255])
        XCTAssertEqual(marked[0, 0], [200, 200, 200, 255])
        XCTAssertNil(PixelDiff.marked(reference: gray(90), actual: gray(90, width: 4, height: 4)))
    }

    // MARK: - Names

    func testNamesAreSafeFileNames() {
        XCTAssertEqual(SnapshotPlan.name(screen: "home", state: "ready", variant: .dark), "home-ready-dark")
        XCTAssertEqual(SnapshotPlan.name(screen: "Onboarding", state: "Step 2/5", variant: .darkLargeType), "onboarding-step-2-5-dark-large-type")
    }

    func testEveryVariantHasItsOwnName() {
        let names = SnapshotVariant.allCases.map { SnapshotPlan.name(screen: "home", state: "ready", variant: $0) }
        XCTAssertEqual(Set(names).count, SnapshotVariant.allCases.count)
    }

    func testTheVariantsCoverLightDarkAndLargeType() {
        XCTAssertEqual(SnapshotVariant.allCases.filter(\.isDark).count, 2)
        XCTAssertEqual(SnapshotVariant.allCases.filter(\.usesLargeType), [.darkLargeType])
        XCTAssertFalse(SnapshotVariant.light.isDark)
    }

    func testReferencesAreKeptForEachVersionOfIOS() {
        XCTAssertEqual(SnapshotPlan.folder(osMajorVersion: 26), "ios26")
    }

    func testThePictureIsAnIPhoneScreen() {
        XCTAssertEqual(SnapshotPlan.width * SnapshotPlan.scale, 780)
        XCTAssertEqual(SnapshotPlan.height * SnapshotPlan.scale, 1688)
    }
}
