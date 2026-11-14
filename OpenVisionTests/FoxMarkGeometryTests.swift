// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class FoxMarkGeometryTests: XCTestCase {
    private typealias Mark = FoxMarkGeometry

    func testTheHeadClosesWhereItStarts() {
        XCTAssertEqual(Mark.head.curves.last?.end, Mark.head.start)
        XCTAssertEqual(Mark.blaze.curves.last?.end, Mark.blaze.start)
        for eye in Mark.eyes {
            XCTAssertEqual(eye.curves.last?.end, eye.start)
        }
    }

    func testTheHeadIsTheSameOnBothSides() {
        let points = Mark.head.points()
        let mirrored = Mark.head.mirrored.points().reversed().map { $0 }
        XCTAssertEqual(points.count, mirrored.count)
        for (one, other) in zip(points, mirrored) {
            XCTAssertEqual(one.x, other.x, accuracy: 1e-9)
            XCTAssertEqual(one.y, other.y, accuracy: 1e-9)
        }
    }

    func testEverythingStaysInsideTheUnitSquare() {
        let outlines = [Mark.head, Mark.blaze] + Mark.eyes
        for point in outlines.flatMap({ $0.points() }) {
            XCTAssertTrue((0...1).contains(point.x), "x \(point.x)")
            XCTAssertTrue((0...1).contains(point.y), "y \(point.y)")
        }
    }

    func testTheEarTipsAreTheHighestPoints() {
        let points = Mark.head.points()
        let top = points.min { $0.y < $1.y }!
        XCTAssertEqual(top.y, 0.03, accuracy: 1e-9)
        XCTAssertEqual(abs(top.x - 0.5), 0.35, accuracy: 1e-9)
    }

    func testTheChinIsOnTheCenterLine() {
        let bottom = Mark.head.points().max { $0.y < $1.y }!
        XCTAssertEqual(bottom.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(bottom.y, 0.97, accuracy: 1e-9)
    }

    func testTheEyesAreAMirroredPairThatDoNotTouchTheBlaze() {
        XCTAssertEqual(Mark.eyes.count, 2)
        XCTAssertEqual(Mark.eyes[1], Mark.eyes[0].mirrored)
        let blazeRight = Mark.blaze.points().map(\.x).max()!
        let eyeLeft = Mark.eyes[0].points().map(\.x).min()!
        XCTAssertGreaterThan(eyeLeft, 0.5)
        // At the height of the eye the blaze is still narrow.
        let blazeAtEye = Mark.blaze.points().filter { $0.y < 0.57 }.map(\.x).max()!
        XCTAssertLessThan(blazeAtEye, eyeLeft)
        XCTAssertLessThan(blazeRight, 0.7)
    }

    func testAnOutlineReadsItsNumbers() {
        let outline = Mark.outline([0, 0, 1, 0, 1, 1, 0, 1])
        XCTAssertEqual(outline.start, Mark.Point(x: 0, y: 0))
        XCTAssertEqual(outline.curves, [
            Mark.Curve(control1: .init(x: 1, y: 0), control2: .init(x: 1, y: 1), end: .init(x: 0, y: 1)),
        ])
        XCTAssertEqual(outline.points(stepsPerCurve: 2).count, 3)
    }
}
