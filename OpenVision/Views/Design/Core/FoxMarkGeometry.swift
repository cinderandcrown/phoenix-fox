// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The Phoenix Fox mark: a fox's face whose ears are two flames.
//
// The shape is written down once, here, in a unit square (x to the right, y down).
// `FoxMark` draws it in the app and `scripts/make_app_icon.py` reads the three number lists
// below out of this file to draw the app icon, so the two cannot drift apart.

import Foundation

enum FoxMarkGeometry {
    struct Point: Equatable, Sendable {
        let x: Double
        let y: Double

        /// The same point on the other side of the face.
        var mirrored: Point { Point(x: 1 - x, y: y) }
    }

    /// One cubic curve, continuing from wherever the outline has reached.
    struct Curve: Equatable, Sendable {
        let control1: Point
        let control2: Point
        let end: Point
    }

    /// A closed outline.
    struct Outline: Equatable, Sendable {
        let start: Point
        let curves: [Curve]

        var mirrored: Outline {
            Outline(
                start: start.mirrored,
                curves: curves.map {
                    Curve(control1: $0.control1.mirrored, control2: $0.control2.mirrored, end: $0.end.mirrored)
                }
            )
        }

        /// Points along the outline, `steps` to a curve. For measuring and for tests.
        func points(stepsPerCurve steps: Int = 24) -> [Point] {
            var result = [start]
            var from = start
            for curve in curves {
                for step in 1...max(steps, 1) {
                    let t = Double(step) / Double(max(steps, 1))
                    let u = 1 - t
                    func blend(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                        u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
                    }
                    result.append(Point(
                        x: blend(from.x, curve.control1.x, curve.control2.x, curve.end.x),
                        y: blend(from.y, curve.control1.y, curve.control2.y, curve.end.y)
                    ))
                }
                from = curve.end
            }
            return result
        }
    }

    // The right half of the head, from the dip between the ears, up the ear to its tip,
    // down the cheek, to the chin. Each row after the first is one curve:
    // control 1, control 2, end.
    static let headHalf: [Double] = [
        0.50, 0.37,
        0.60, 0.36, 0.76, 0.24, 0.85, 0.03,
        0.91, 0.16, 0.95, 0.34, 0.92, 0.49,
        0.88, 0.70, 0.66, 0.86, 0.50, 0.97,
    ]

    // The right half of the blaze, the pale flame from the brow to the chin.
    static let blazeHalf: [Double] = [
        0.50, 0.44,
        0.53, 0.54, 0.64, 0.60, 0.64, 0.71,
        0.64, 0.82, 0.56, 0.91, 0.50, 0.97,
    ]

    // The right eye, a whole outline.
    static let rightEye: [Double] = [
        0.585, 0.555,
        0.62, 0.47, 0.71, 0.43, 0.79, 0.42,
        0.77, 0.51, 0.68, 0.565, 0.585, 0.555,
    ]

    static let head = symmetric(headHalf)
    static let blaze = symmetric(blazeHalf)
    static let eyes = [outline(rightEye), outline(rightEye).mirrored]

    /// Reads a number list as a start point and then curves.
    static func outline(_ numbers: [Double]) -> Outline {
        precondition(numbers.count >= 8 && (numbers.count - 2) % 6 == 0, "A start point, then six numbers a curve")
        let curves = stride(from: 2, to: numbers.count, by: 6).map { index in
            Curve(
                control1: Point(x: numbers[index], y: numbers[index + 1]),
                control2: Point(x: numbers[index + 2], y: numbers[index + 3]),
                end: Point(x: numbers[index + 4], y: numbers[index + 5])
            )
        }
        return Outline(start: Point(x: numbers[0], y: numbers[1]), curves: curves)
    }

    /// Completes a right half that starts and ends on the center line with its mirror image.
    static func symmetric(_ half: [Double]) -> Outline {
        let right = outline(half)
        var from = right.start
        var back: [Curve] = []
        for curve in right.curves {
            // The same curve walked the other way, on the other side.
            back.append(Curve(control1: curve.control2.mirrored, control2: curve.control1.mirrored, end: from.mirrored))
            from = curve.end
        }
        return Outline(start: right.start, curves: right.curves + back.reversed())
    }
}
