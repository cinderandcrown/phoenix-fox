// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

/// The brand colors hold their contrast in both appearances.
final class BrandPaletteTests: XCTestCase {
    func testContrastOfBlackOnWhiteIsTwentyOne() {
        XCTAssertEqual(Swatch.contrast(Swatch(0x000000), Swatch(0xFFFFFF)), 21, accuracy: 0.001)
        XCTAssertEqual(Swatch.contrast(Swatch(0xFFFFFF), Swatch(0x000000)), 21, accuracy: 0.001)
        XCTAssertEqual(Swatch.contrast(Swatch(0x777777), Swatch(0x777777)), 1, accuracy: 0.001)
    }

    func testContrastMatchesAPublishedExample() {
        // WebAIM's checker gives 4.54 to 1 for #767676 on white, the lightest gray that passes.
        XCTAssertEqual(Swatch.contrast(Swatch(0x767676), Swatch(0xFFFFFF)), 4.54, accuracy: 0.01)
    }

    func testHexRoundTrips() {
        XCTAssertEqual(Swatch(0xFF5A1F).hex, "#FF5A1F")
        XCTAssertEqual(Swatch(0x0D0A09).hex, "#0D0A09")
    }

    func testAColorLaidOverAnotherBlends() {
        let white = Swatch(0xFFFFFF), black = Swatch(0x000000)
        XCTAssertEqual(white.over(black, opacity: 0), black)
        XCTAssertEqual(white.over(black, opacity: 1), white)
        XCTAssertEqual(white.over(black, opacity: 0.5).hex, "#808080")
    }

    func testEveryPairingMeetsItsMinimumInLightAndInDark() {
        for pairing in BrandPalette.pairings {
            for isDark in [false, true] {
                let ratio = Swatch.contrast(pairing.front.value(dark: isDark), pairing.back.value(dark: isDark))
                XCTAssertGreaterThanOrEqual(
                    ratio, pairing.minimum,
                    "\(pairing.front.name) on \(pairing.back.name), \(isDark ? "dark" : "light"): \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    func testThePairingsCoverEveryInkOnEveryGround() {
        XCTAssertEqual(BrandPalette.pairings.count, 3 * 7 + 3)
    }

    func testWhiteOnEmberWouldNotPassWhichIsWhyTheLabelIsDark() {
        XCTAssertLessThan(Swatch.contrast(Swatch(0xFFFFFF), BrandPalette.ember.dark), BrandPalette.textMinimum)
    }

    func testTheGroundsStepApartSoACardShowsOnTheCanvas() {
        for isDark in [false, true] {
            let canvas = BrandPalette.canvas.value(dark: isDark).luminance
            let surface = BrandPalette.surface.value(dark: isDark).luminance
            XCTAssertNotEqual(canvas, surface)
            // By night a card is lighter than the canvas; by day it is too.
            XCTAssertGreaterThan(surface, canvas)
        }
    }

    func testColorNamesAreUnique() {
        let names = BrandPalette.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testOnlyTheCameraIsThatRed() {
        // Nothing else in the palette may be mistaken for the capture light.
        let seeing = BrandPalette.seeing
        for color in BrandPalette.all where color != seeing {
            XCTAssertNotEqual(color.dark, seeing.dark)
            XCTAssertNotEqual(color.light, seeing.light)
        }
    }
}
