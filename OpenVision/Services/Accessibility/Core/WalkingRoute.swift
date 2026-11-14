// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Follows a walking route and says each turn at the right moment.
//
// The map service gives a list of steps. This file tracks which step the wearer is on from
// location fixes alone, announces a turn before it and again at it, notices when they have
// left the route, and says when they have arrived. It holds no map and no location
// manager, so every decision can be tested with plain coordinates.

import Foundation

struct Coordinate: Equatable, Sendable {
    var latitude: Double
    var longitude: Double

    init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in meters.
    func distance(to other: Coordinate) -> Double {
        let radius = 6_371_000.0
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return radius * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    /// Compass bearing toward another point, in degrees from north, 0 to 360.
    func bearing(to other: Coordinate) -> Double {
        let lat1 = latitude * .pi / 180, lat2 = other.latitude * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Distance in meters to the nearest point of a path. Over the length of a city block
    /// the ground is flat enough to measure on a plane.
    func distance(toPath path: [Coordinate]) -> Double {
        guard let first = path.first else { return .greatestFiniteMagnitude }
        guard path.count > 1 else { return distance(to: first) }
        let metersPerLat = 111_320.0
        let metersPerLon = 111_320.0 * cos(latitude * .pi / 180)
        func local(_ point: Coordinate) -> (x: Double, y: Double) {
            ((point.longitude - longitude) * metersPerLon, (point.latitude - latitude) * metersPerLat)
        }
        var best = Double.greatestFiniteMagnitude
        for index in 1..<path.count {
            let a = local(path[index - 1]), b = local(path[index])
            let dx = b.x - a.x, dy = b.y - a.y
            let length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, -(a.x * dx + a.y * dy) / length))
            let px = a.x + t * dx, py = a.y + t * dy
            best = min(best, (px * px + py * py).squareRoot())
        }
        return best
    }
}

struct WalkingRoute: Equatable, Sendable {
    struct Step: Equatable, Sendable {
        /// What to do at the start of this stretch: "Turn right onto Main Street".
        var instruction: String
        /// The path walked during this step. Its first point is where the instruction applies.
        var path: [Coordinate]

        var length: Double {
            zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        }
    }

    var destination: String
    var steps: [Step]

    var length: Double { steps.reduce(0) { $0 + $1.length } }
}

/// One location reading.
struct LocationFix: Equatable, Sendable {
    var coordinate: Coordinate
    /// The radius of uncertainty in meters, as the system reports it.
    var accuracy: Double
    /// Direction of travel in degrees from north, or nil when standing still.
    var course: Double?
}

enum RouteEvent: Equatable, Sendable {
    case say(String)
    case arrived(String)
    /// The wearer has been away from the route for several fixes. Ask for a new one.
    case offRoute
}

struct RouteProgress: Sendable {
    let route: WalkingRoute
    let metric: Bool
    private(set) var stepIndex = 0
    private var warnedNext = false
    private var strayFixes = 0
    private var started = false
    private(set) var finished = false

    init(route: WalkingRoute, metric: Bool) {
        self.route = route
        self.metric = metric
    }

    /// The first thing to say when guidance begins.
    mutating func begin() -> String {
        started = true
        let total = Distance.spoken(route.length, metric: metric)
        guard let first = route.steps.first else { return "I have no steps for that route." }
        return "Walking to \(route.destination), \(total). \(first.instruction)."
    }

    /// What to say now, if asked: the current instruction and how far the next turn is.
    func status(at fix: LocationFix?) -> String {
        guard !finished, route.steps.indices.contains(stepIndex) else { return "You have arrived at \(route.destination)." }
        guard let next = nextTurn, let fix else { return route.steps[stepIndex].instruction + "." }
        let away = Distance.spoken(fix.coordinate.distance(to: next.at), metric: metric)
        var line = "In \(away), \(next.instruction.lowercasedFirst)."
        if let clock = Self.clock(from: fix, to: next.at) { line += " It's at your \(clock) o'clock." }
        return line
    }

    mutating func update(_ fix: LocationFix) -> [RouteEvent] {
        guard started, !finished, route.steps.indices.contains(stepIndex) else { return [] }
        // A fix that is vaguer than a street is wide cannot place a turn. Wait for a better one.
        guard fix.accuracy >= 0, fix.accuracy <= 65 else { return [] }
        let reach = max(12, min(fix.accuracy, 25))

        guard let next = nextTurn else {
            // Last step: the only thing left is the destination.
            if let end = route.steps[stepIndex].path.last, fix.coordinate.distance(to: end) <= reach + 5 {
                finished = true
                return [.arrived("You have arrived. \(route.destination.uppercasedFirst) should be within a few steps.")]
            }
            return strayed(fix)
        }

        let away = fix.coordinate.distance(to: next.at)
        if away <= reach {
            stepIndex += 1
            warnedNext = false
            strayFixes = 0
            return [.say("\(next.instruction) now.")]
        }
        if !warnedNext, away <= 40 {
            warnedNext = true
            return [.say("In \(Distance.spoken(away, metric: metric)), \(next.instruction.lowercasedFirst).")]
        }
        return strayed(fix)
    }

    private var nextTurn: (instruction: String, at: Coordinate)? {
        let index = stepIndex + 1
        guard route.steps.indices.contains(index), let at = route.steps[index].path.first else { return nil }
        return (route.steps[index].instruction, at)
    }

    /// Three fixes in a row well away from the current stretch means a wrong turn, not a
    /// stray reading between tall buildings.
    private mutating func strayed(_ fix: LocationFix) -> [RouteEvent] {
        let path = route.steps[stepIndex].path
        let allowed = max(30, fix.accuracy * 2)
        if fix.coordinate.distance(toPath: path) > allowed {
            strayFixes += 1
            if strayFixes >= 3 {
                strayFixes = 0
                return [.offRoute]
            }
        } else {
            strayFixes = 0
        }
        return []
    }

    /// The turn's direction as a clock hour relative to the way the wearer is walking.
    static func clock(from fix: LocationFix, to point: Coordinate) -> Int? {
        guard let course = fix.course, course >= 0 else { return nil }
        var relative = fix.coordinate.bearing(to: point) - course
        if relative < 0 { relative += 360 }
        let hour = Int((relative / 30).rounded()) % 12
        return hour == 0 ? 12 : hour
    }
}

enum Distance {
    /// A distance the way a person says it: rounded, never falsely exact.
    static func spoken(_ meters: Double, metric: Bool) -> String {
        if metric {
            if meters < 1000 {
                let rounded = max(5, Int((meters / 5).rounded()) * 5)
                return "\(rounded) meters"
            }
            return String(format: "%.1f kilometers", meters / 1000)
        }
        let feet = meters * 3.28084
        if feet < 1000 {
            let rounded = max(10, Int((feet / 10).rounded()) * 10)
            return "\(rounded) feet"
        }
        let miles = meters / 1609.344
        return String(format: "%.1f miles", miles)
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }

    var uppercasedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
