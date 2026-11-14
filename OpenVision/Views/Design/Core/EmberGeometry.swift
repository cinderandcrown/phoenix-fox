// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The shape of the live orb: a coal that breathes.
//
// The outline is a circle whose radius is pushed in and out by a few sine waves that travel
// around it. Each mood sets how strong each wave is. The waves themselves never change
// speed, so moving from one mood to another is a matter of fading strengths, and the
// outline never jumps. `EmberOrb` draws what this file works out.

import Foundation

enum EmberGeometry {
    /// One wave travelling around the outline.
    struct Wave: Equatable, Sendable {
        /// Whole bumps around the circle. A whole number keeps the outline closed.
        let lobes: Int
        /// Radians a second. Negative runs the other way.
        let speed: Double
    }

    /// A slow drift, a roll, a flicker, and a shimmer.
    static let waves: [Wave] = [
        Wave(lobes: 2, speed: 0.6),
        Wave(lobes: 3, speed: -1.1),
        Wave(lobes: 5, speed: 2.9),
        Wave(lobes: 7, speed: -4.3),
    ]

    /// How fast the whole orb swells and settles, in radians a second.
    static let breathSpeed = 2.2

    /// How the orb looks in one mood. Every number fades smoothly into another mood's.
    struct Look: Equatable, Sendable {
        /// The strength of each wave in `waves`, as a share of the radius.
        var strengths: [Double]
        /// The size at rest, where 1 fills the space given.
        var size: Double
        /// How far the size swells and settles.
        var breath: Double
        /// From 0, a banked coal, to 1, white-hot.
        var heat: Double

        /// The furthest the outline can be pushed from a circle.
        var reach: Double { strengths.reduce(0) { $0 + abs($1) } }

        /// This look, part of the way to another. `progress` runs from 0 to 1.
        func mixed(with other: Look, progress: Double) -> Look {
            let t = EmberGeometry.eased(progress)
            func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
            return Look(
                strengths: zip(strengths, other.strengths).map(mix),
                size: mix(size, other.size),
                breath: mix(breath, other.breath),
                heat: mix(heat, other.heat)
            )
        }
    }

    static func look(for mood: OrbMood) -> Look {
        switch mood {
        case .resting:
            // Banked: small, dim, barely moving.
            return Look(strengths: [0.030, 0.018, 0, 0], size: 0.78, breath: 0.012, heat: 0.25)
        case .listening:
            // Drawn tight and bright, and still, the way a person leans in.
            return Look(strengths: [0.012, 0.010, 0, 0], size: 0.86, breath: 0.006, heat: 1)
        case .thinking:
            // Flickering.
            return Look(strengths: [0.025, 0.035, 0.032, 0.018], size: 0.82, breath: 0.010, heat: 0.6)
        case .replying:
            // Open and rolling, swelling with the voice.
            return Look(strengths: [0.045, 0.038, 0.016, 0], size: 0.87, breath: 0.035, heat: 0.8)
        }
    }

    /// Smooth start and stop for a value from 0 to 1. Values outside are clamped.
    static func eased(_ progress: Double) -> Double {
        let t = min(max(progress, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// The radius at `angle`, as a multiple of the orb's own radius.
    ///
    /// `layer` offsets the waves so the layers of the orb do not move as one.
    static func radius(angle: Double, time: Double, look: Look, layer: Int = 0) -> Double {
        var radius = 1.0
        for (wave, strength) in zip(waves, look.strengths) where strength != 0 {
            let phase = Double(layer) * 1.7 + Double(wave.lobes)
            radius += strength * sin(Double(wave.lobes) * angle + wave.speed * time + phase)
        }
        return radius
    }

    /// The size of the whole orb at `time`, where 1 fills the space given.
    static func size(time: Double, look: Look) -> Double {
        look.size + look.breath * sin(breathSpeed * time)
    }

    /// Points around the outline in a unit square, centered on (0.5, 0.5).
    ///
    /// `scale` shrinks a layer toward the center: the core of the orb is the same shape,
    /// smaller.
    static func outline(time: Double, look: Look, layer: Int = 0, scale: Double = 1, points count: Int = 72) -> [(x: Double, y: Double)] {
        let count = max(count, 8)
        let size = size(time: time, look: look) * scale * 0.5
        return (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi
            let radius = radius(angle: angle, time: time, look: look, layer: layer) * size
            return (x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
        }
    }

    /// The largest share of the space the orb can ever fill, for any mood.
    static var largestExtent: Double {
        OrbMood.allCases.map { mood in
            let look = look(for: mood)
            return (look.size + look.breath) * (1 + look.reach)
        }.max() ?? 1
    }
}
