// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class EmberGeometryTests: XCTestCase {
    private typealias Ember = EmberGeometry

    func testEveryMoodHasAStrengthForEveryWave() {
        for mood in OrbMood.allCases {
            XCTAssertEqual(Ember.look(for: mood).strengths.count, Ember.waves.count, mood.rawValue)
        }
    }

    func testTheOutlineNeverLeavesItsSpace() {
        XCTAssertLessThanOrEqual(Ember.largestExtent, 1)
        for mood in OrbMood.allCases {
            let look = Ember.look(for: mood)
            for step in 0..<200 {
                let time = Double(step) * 0.173
                for point in Ember.outline(time: time, look: look) {
                    XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y), "\(mood) at \(time)")
                }
            }
        }
    }

    func testTheRadiusStaysWithinTheReachOfItsWaves() {
        for mood in OrbMood.allCases {
            let look = Ember.look(for: mood)
            for step in 0..<500 {
                let radius = Ember.radius(angle: Double(step) * 0.37, time: Double(step) * 0.091, look: look)
                XCTAssertLessThanOrEqual(abs(radius - 1), look.reach + 1e-12)
            }
        }
    }

    func testTheOutlineClosesBecauseEveryWaveHasWholeLobes() {
        for mood in OrbMood.allCases {
            let look = Ember.look(for: mood)
            for time in [0.0, 1.3, 77.7] {
                XCTAssertEqual(
                    Ember.radius(angle: 0, time: time, look: look),
                    Ember.radius(angle: 2 * .pi, time: time, look: look),
                    accuracy: 1e-9
                )
            }
        }
    }

    func testTheOutlineMovesWithTime() {
        let look = Ember.look(for: .thinking)
        XCTAssertNotEqual(
            Ember.radius(angle: 1, time: 0, look: look),
            Ember.radius(angle: 1, time: 0.5, look: look)
        )
    }

    func testAtAFixedTimeTheOutlineIsTheSameEveryTime() {
        // Previews, snapshot tests, and Reduce Motion all hold the clock still.
        let look = Ember.look(for: .replying)
        let once = Ember.outline(time: 3, look: look)
        let again = Ember.outline(time: 3, look: look)
        XCTAssertEqual(once.map(\.x), again.map(\.x))
        XCTAssertEqual(once.map(\.y), again.map(\.y))
    }

    func testListeningIsTheHottestAndStillestAndRestingTheCoolest() {
        let looks = Dictionary(uniqueKeysWithValues: OrbMood.allCases.map { ($0, Ember.look(for: $0)) })
        XCTAssertEqual(looks[.listening]!.heat, looks.values.map(\.heat).max())
        XCTAssertEqual(looks[.resting]!.heat, looks.values.map(\.heat).min())
        XCTAssertEqual(looks[.listening]!.reach, looks.values.map(\.reach).min())
        XCTAssertEqual(looks[.thinking]!.reach, looks.values.map(\.reach).max())
        XCTAssertEqual(looks[.replying]!.breath, looks.values.map(\.breath).max())
    }

    func testTheFourMoodsLookDifferent() {
        let looks = OrbMood.allCases.map { Ember.look(for: $0) }
        for (index, look) in looks.enumerated() {
            for other in looks[(index + 1)...] {
                XCTAssertNotEqual(look, other)
            }
        }
    }

    func testMixingStartsAtOneLookAndEndsAtTheOther() {
        let from = Ember.look(for: .resting), to = Ember.look(for: .replying)
        XCTAssertEqual(from.mixed(with: to, progress: 0), from)
        XCTAssertEqual(from.mixed(with: to, progress: 1), to)
        XCTAssertEqual(from.mixed(with: to, progress: 7), to)
        XCTAssertEqual(from.mixed(with: to, progress: -1), from)
        let half = from.mixed(with: to, progress: 0.5)
        XCTAssertEqual(half.heat, (from.heat + to.heat) / 2, accuracy: 1e-12)
        XCTAssertEqual(half.size, (from.size + to.size) / 2, accuracy: 1e-12)
    }

    func testAChangeOfMoodNeverMakesTheOutlineJump() {
        // A small step in progress is a small step in the radius, at any moment.
        let from = Ember.look(for: .listening), to = Ember.look(for: .thinking)
        for step in 0..<100 {
            let progress = Double(step) / 100
            let before = Ember.radius(angle: 2, time: 9.4, look: from.mixed(with: to, progress: progress))
            let after = Ember.radius(angle: 2, time: 9.4, look: from.mixed(with: to, progress: progress + 0.01))
            XCTAssertLessThan(abs(after - before), 0.005)
        }
    }

    func testEasingIsSmoothAtBothEnds() {
        XCTAssertEqual(Ember.eased(0), 0)
        XCTAssertEqual(Ember.eased(1), 1)
        XCTAssertEqual(Ember.eased(0.5), 0.5, accuracy: 1e-12)
        XCTAssertLessThan(Ember.eased(0.1), 0.1)
        XCTAssertGreaterThan(Ember.eased(0.9), 0.9)
    }

    func testTheLayersDoNotMoveAsOne() {
        let look = Ember.look(for: .thinking)
        XCTAssertNotEqual(
            Ember.radius(angle: 1, time: 2, look: look, layer: 0),
            Ember.radius(angle: 1, time: 2, look: look, layer: 1)
        )
    }

    func testAnInnerLayerIsTheSameShapeSmaller() {
        let look = Ember.look(for: .resting)
        let outer = Ember.outline(time: 1, look: look, points: 16)
        let inner = Ember.outline(time: 1, look: look, scale: 0.5, points: 16)
        for (a, b) in zip(outer, inner) {
            XCTAssertEqual(b.x - 0.5, (a.x - 0.5) / 2, accuracy: 1e-12)
            XCTAssertEqual(b.y - 0.5, (a.y - 0.5) / 2, accuracy: 1e-12)
        }
    }
}
