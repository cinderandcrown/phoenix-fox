// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI
import XCTest
@testable import PhoenixFox

/// Pictures of the home screen and of first run, in dark mode, light mode, and at an
/// accessibility text size. A change to how either looks shows up here as a failed test
/// with a picture of what changed.
@MainActor
final class DesignSnapshotTests: XCTestCase {
    func testHomeScreen() {
        for sample in HomeSamples.all {
            for variant in SnapshotVariant.allCases {
                SnapshotHarness.check(
                    HomeContent(model: sample.model),
                    named: SnapshotPlan.name(screen: "home", state: sample.name, variant: variant),
                    variant: variant,
                    in: self
                )
            }
        }
    }

    func testOnboarding() {
        for step in OnboardingStep.allCases {
            for variant in SnapshotVariant.allCases {
                SnapshotHarness.check(
                    OnboardingSamples.page(step),
                    named: SnapshotPlan.name(screen: "onboarding", state: "\(step)", variant: variant),
                    variant: variant,
                    in: self
                )
            }
        }
    }

    func testTheSamePictureIsDrawnTwice() throws {
        // If this fails, something on the screen moves on its own and no reference would
        // ever match. It needs no reference, so it means something from the first run on.
        let first = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(HomeContent(model: HomeSamples.asking), variant: .dark)))
        let second = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(HomeContent(model: HomeSamples.asking), variant: .dark)))
        let verdict = PixelDiff.compare(reference: first, actual: second)
        XCTAssertTrue(verdict.passes, verdict.summary)
    }

    func testLightAndDarkAreDifferentPictures() throws {
        // Guards the harness itself: the color scheme given to it reaches the screen.
        let dark = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(HomeContent(model: HomeSamples.ready), variant: .dark)))
        let light = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(HomeContent(model: HomeSamples.ready), variant: .light)))
        XCTAssertFalse(PixelDiff.compare(reference: dark, actual: light).passes)
    }

    func testLargeTypeIsADifferentPicture() throws {
        let regular = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(OnboardingSamples.page(.welcome), variant: .dark)))
        let large = try XCTUnwrap(SnapshotHarness.pixels(of: SnapshotHarness.draw(OnboardingSamples.page(.welcome), variant: .darkLargeType)))
        XCTAssertFalse(PixelDiff.compare(reference: regular, actual: large).passes)
    }
}
