// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Names the color of what the wearer is holding up, for matching clothes or sorting laundry.
//
// Distances are measured in CIELAB, where equal steps look about equally different to the
// eye. Comparing raw red, green, and blue values calls a dark navy "black" and a tan
// "orange" far more often.

import Foundation

struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// Channel values from 0 to 255.
    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

struct Lab: Equatable, Sendable {
    var l: Double
    var a: Double
    var b: Double

    var chroma: Double { (a * a + b * b).squareRoot() }

    func distance(to other: Lab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// sRGB to CIELAB under the D65 white point.
    init(_ color: RGB) {
        func linear(_ value: Double) -> Double {
            let unit = min(max(value / 255, 0), 1)
            return unit <= 0.04045 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
        }
        let r = linear(color.red), g = linear(color.green), b = linear(color.blue)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func curve(_ value: Double) -> Double {
            value > 216.0 / 24389.0 ? cbrt(value) : (24389.0 / 27.0 * value + 16) / 116
        }
        let fx = curve(x), fy = curve(y), fz = curve(z)
        l = 116 * fy - 16
        a = 500 * (fx - fy)
        self.b = 200 * (fy - fz)
    }
}

enum ColorNamer {
    /// What was seen, in the words to say.
    struct Reading: Equatable, Sendable {
        /// The main color, then a second one when it covers a real share of the sample.
        var names: [String]
        /// True when the sample was too dark to trust.
        var dim: Bool

        var spoken: String {
            guard let first = names.first else { return "I couldn't see a color. Hold it closer to the glasses." }
            let color = names.count > 1 ? "mostly \(first), with \(names[1])" : first
            return dim
                ? "It looks \(color), but the light is low, so I'm less sure. Colors also shift under warm bulbs."
                : "It looks \(color)."
        }
    }

    /// The nearest everyday name for one color.
    static func name(_ color: RGB) -> String {
        let lab = Lab(color)
        // Near the gray axis hue is noise, so lightness alone picks the name.
        if lab.chroma < 9 {
            switch lab.l {
            case ..<18: return "black"
            case ..<42: return "dark gray"
            case ..<68: return "gray"
            case ..<88: return "light gray"
            default: return "white"
            }
        }
        var best = palette[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for entry in palette {
            let distance = lab.distance(to: entry.lab)
            if distance < bestDistance {
                best = entry
                bestDistance = distance
            }
        }
        return best.name
    }

    /// Describes a patch of pixels: the color most of them share, and a second color when
    /// at least a quarter of them share it, which is how a stripe or a print shows up.
    static func describe(_ samples: [RGB]) -> Reading {
        guard !samples.isEmpty else { return Reading(names: [], dim: false) }
        var votes: [String: Int] = [:]
        var light = 0.0
        for sample in samples {
            votes[name(sample), default: 0] += 1
            light += Lab(sample).l
        }
        let ranked = votes.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var names = [ranked[0].key]
        if ranked.count > 1, Double(ranked[1].value) >= Double(samples.count) * 0.25 {
            names.append(ranked[1].key)
        }
        return Reading(names: names, dim: light / Double(samples.count) < 22)
    }

    private struct Entry {
        var name: String
        var lab: Lab
    }

    /// Names a person would use for clothes. Each has one reference color; the nearest wins.
    private static let palette: [Entry] = [
        ("red", RGB(204, 30, 36)), ("dark red", RGB(128, 20, 28)), ("maroon", RGB(96, 24, 40)),
        ("pink", RGB(244, 150, 180)), ("hot pink", RGB(232, 50, 130)), ("light pink", RGB(250, 205, 215)),
        ("orange", RGB(240, 130, 30)), ("coral", RGB(244, 120, 96)), ("peach", RGB(250, 200, 160)),
        ("yellow", RGB(248, 222, 50)), ("mustard yellow", RGB(205, 160, 40)), ("cream", RGB(248, 240, 205)),
        ("brown", RGB(110, 70, 40)), ("dark brown", RGB(66, 42, 28)), ("tan", RGB(196, 160, 116)),
        ("beige", RGB(222, 204, 174)), ("khaki", RGB(170, 150, 100)),
        ("green", RGB(40, 150, 70)), ("dark green", RGB(24, 82, 44)), ("light green", RGB(160, 220, 150)),
        ("olive green", RGB(104, 110, 44)), ("lime green", RGB(160, 214, 40)), ("mint green", RGB(176, 232, 204)),
        ("teal", RGB(20, 128, 128)), ("turquoise", RGB(60, 200, 196)),
        ("blue", RGB(36, 96, 200)), ("navy blue", RGB(26, 38, 84)), ("light blue", RGB(150, 200, 240)),
        ("sky blue", RGB(100, 170, 235)), ("denim blue", RGB(74, 104, 150)),
        ("purple", RGB(118, 50, 160)), ("dark purple", RGB(64, 28, 88)), ("lavender", RGB(196, 176, 232)),
        ("magenta", RGB(196, 40, 160)), ("burgundy", RGB(110, 20, 50)),
    ].map { Entry(name: $0.0, lab: Lab($0.1)) }
}
