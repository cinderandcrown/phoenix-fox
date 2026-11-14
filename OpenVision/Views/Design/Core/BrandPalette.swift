// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The Phoenix Fox colors, as numbers.
//
// Every color has a light and a dark value. This file has no SwiftUI in it so that the
// contrast of each pairing can be checked by a unit test: `BrandPalette.pairings` is the
// list of what is drawn on what, and how much contrast each needs. docs/DESIGN.md has the
// reasons for the choices.

import Foundation

/// An opaque sRGB color.
struct Swatch: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xFF5A1F` is red 255, green 90, blue 31.
    init(_ hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// "#FF5A1F".
    var hex: String {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    /// Relative luminance, as WCAG 2 defines it.
    var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The WCAG 2 contrast ratio between two colors, from 1 to 21.
    static func contrast(_ one: Swatch, _ other: Swatch) -> Double {
        let high = max(one.luminance, other.luminance)
        let low = min(one.luminance, other.luminance)
        return (high + 0.05) / (low + 0.05)
    }

    /// This color at `opacity`, laid over `background`.
    func over(_ background: Swatch, opacity: Double) -> Swatch {
        let amount = min(max(opacity, 0), 1)
        return Swatch(
            red: red * amount + background.red * (1 - amount),
            green: green * amount + background.green * (1 - amount),
            blue: blue * amount + background.blue * (1 - amount)
        )
    }
}

/// One color in both appearances.
struct BrandColor: Equatable, Sendable {
    let name: String
    let light: Swatch
    let dark: Swatch

    init(_ name: String, light: UInt32, dark: UInt32) {
        self.name = name
        self.light = Swatch(light)
        self.dark = Swatch(dark)
    }

    /// The same value in both appearances.
    init(_ name: String, _ both: UInt32) {
        self.init(name, light: both, dark: both)
    }

    func value(dark isDark: Bool) -> Swatch { isDark ? dark : light }
}

enum BrandPalette {
    // MARK: Fire. The same in both appearances, and never used for small text.

    /// The brand color. Fills the main button, the live orb, and the selected tab.
    static let ember = BrandColor("Ember", 0xFF5A1F)
    /// The lighter end of the fire gradient.
    static let flame = BrandColor("Flame", 0xFF8A1F)
    /// The hottest part: highlights, and the orb while it listens.
    static let gold = BrandColor("Gold", 0xFFC247)
    /// The deep end of the fire gradient, and the glow behind the orb.
    static let garnet = BrandColor("Garnet", 0xA61B1B)
    /// Words and symbols drawn on an ember, flame, or gold fill.
    static let onFire = BrandColor("On fire", 0x1F0D05)

    // MARK: Ground. What the app is drawn on.

    /// The screen behind everything: warm parchment by day, warm black by night.
    static let canvas = BrandColor("Canvas", light: 0xFBF5EE, dark: 0x0D0A09)
    /// A card.
    static let surface = BrandColor("Surface", light: 0xFFFFFF, dark: 0x1A1412)
    /// A well inside a card, or a card that sits on another.
    static let raised = BrandColor("Raised", light: 0xF4EAE0, dark: 0x251C19)

    // MARK: Ink. Words and symbols on the ground.

    static let ink = BrandColor("Ink", light: 0x1E1410, dark: 0xFFF6ED)
    /// Secondary words.
    static let inkSoft = BrandColor("Soft ink", light: 0x655246, dark: 0xCBB9AB)
    /// Captions and timestamps. The faintest words allowed.
    static let inkFaint = BrandColor("Faint ink", light: 0x7A675B, dark: 0x9C8A7D)
    /// The brand color where it has to be read: links, symbols, the word under the orb.
    static let emberInk = BrandColor("Ember ink", light: 0xB5380A, dark: 0xFF7A3D)
    static let goldInk = BrandColor("Gold ink", light: 0x8A5A00, dark: 0xFFC247)

    // MARK: Meaning.

    /// The camera is on. Matches the capture light on the glasses, and nothing else is this red.
    static let seeing = BrandColor("Seeing", light: 0xC4221A, dark: 0xFF5A52)
    /// Words and symbols on a `seeing` fill.
    static let onSeeing = BrandColor("On seeing", light: 0xFFFFFF, dark: 0x1F0D05)
    /// Connected, allowed, done.
    static let good = BrandColor("Good", light: 0x1E7A45, dark: 0x5BD68A)

    static let all: [BrandColor] = [
        ember, flame, gold, garnet, onFire,
        canvas, surface, raised,
        ink, inkSoft, inkFaint, emberInk, goldInk,
        seeing, onSeeing, good,
    ]

    // MARK: What is drawn on what

    /// Something drawn on something else, and the least contrast it may have.
    struct Pairing: Sendable {
        let front: BrandColor
        let back: BrandColor
        let minimum: Double
    }

    /// Body text. WCAG 2.2 level AA.
    static let textMinimum = 4.5
    /// Symbols and the edges of controls. WCAG 2.2 level AA, success criterion 1.4.11.
    static let symbolMinimum = 3.0

    /// Every pairing the app uses. A view that needs a new one adds it here first.
    static let pairings: [Pairing] = {
        let grounds = [canvas, surface, raised]
        let inks = [ink, inkSoft, inkFaint, emberInk, goldInk, seeing, good]
        var list = grounds.flatMap { ground in
            inks.map { Pairing(front: $0, back: ground, minimum: textMinimum) }
        }
        list += [ember, flame, gold].map { Pairing(front: onFire, back: $0, minimum: textMinimum) }
        list.append(Pairing(front: onSeeing, back: seeing, minimum: textMinimum))
        return list
    }()
}
