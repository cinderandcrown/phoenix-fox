// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The look of Phoenix Fox, in one place: colors, type, spacing, shapes, and motion.
//
// The color values and the contrast rules they must meet are in `BrandPalette`. This file
// turns them into SwiftUI colors that follow light and dark mode, and adds the few shared
// pieces every screen uses. docs/DESIGN.md explains the choices.

import SwiftUI
import UIKit

extension Color {
    /// A brand color that follows light and dark mode.
    init(_ brand: BrandColor) {
        self.init(uiColor: UIColor(brand))
    }

    /// One fixed value, the same in light and dark.
    init(_ swatch: Swatch) {
        self.init(red: swatch.red, green: swatch.green, blue: swatch.blue)
    }
}

extension UIColor {
    convenience init(_ brand: BrandColor) {
        self.init { traits in
            UIColor(brand.value(dark: traits.userInterfaceStyle == .dark))
        }
    }

    convenience init(_ swatch: Swatch) {
        self.init(red: swatch.red, green: swatch.green, blue: swatch.blue, alpha: 1)
    }
}

enum Theme {
    // MARK: - Fire

    /// The brand color, for fills: the main button, the orb, a selected chip.
    static let ember = Color(BrandPalette.ember)
    static let flame = Color(BrandPalette.flame)
    static let gold = Color(BrandPalette.gold)
    static let garnet = Color(BrandPalette.garnet)
    /// Words and symbols on an ember, flame, or gold fill.
    static let onFire = Color(BrandPalette.onFire)

    // MARK: - Ground

    static let canvas = Color(BrandPalette.canvas)
    static let surface = Color(BrandPalette.surface)
    static let raised = Color(BrandPalette.raised)
    /// The hairline around a card.
    static let hairline = Color(BrandPalette.ink).opacity(0.10)

    // MARK: - Ink

    static let ink = Color(BrandPalette.ink)
    static let inkSoft = Color(BrandPalette.inkSoft)
    /// Captions and timestamps. With Increase Contrast on, this is the soft ink.
    static let inkFaint = Color(uiColor: UIColor { traits in
        let color = traits.accessibilityContrast == .high ? BrandPalette.inkSoft : BrandPalette.inkFaint
        return UIColor(color.value(dark: traits.userInterfaceStyle == .dark))
    })
    /// The brand color where it has to be read: links, symbols, tints.
    static let emberInk = Color(BrandPalette.emberInk)
    static let goldInk = Color(BrandPalette.goldInk)

    // MARK: - Meaning

    /// The camera is on. Nothing else in the app is this red.
    static let seeing = Color(BrandPalette.seeing)
    static let onSeeing = Color(BrandPalette.onSeeing)
    static let good = Color(BrandPalette.good)

    // MARK: - Names older screens use

    static let accent = emberInk
    static let accentBright = gold
    static let accentDeep = garnet
    static let glow = flame
    static let bg = canvas
    static let bgElevated = surface
    static let bgElevatedStroke = hairline
    static let textPrimary = ink
    static let textSecondary = inkSoft
    static let heading = ink
    static let glass = Color(BrandPalette.ink).opacity(0.05)

    // MARK: - Gradients

    /// The fire, from its deep base to its bright tip.
    static var fire: LinearGradient {
        LinearGradient(colors: [gold, flame, ember], startPoint: .top, endPoint: .bottom)
    }

    /// The main button. Lit from above.
    static var buttonGradient: LinearGradient {
        LinearGradient(colors: [flame, ember], startPoint: .top, endPoint: .bottom)
    }

    static var ringGradient: AngularGradient {
        AngularGradient(colors: [gold, ember, garnet, ember, gold], center: .center)
    }

    static var loopGradient: LinearGradient {
        LinearGradient(colors: [gold, flame, ember.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
    }

    /// Warmth behind the orb.
    static func glowGradient(_ opacity: Double = 0.9) -> RadialGradient {
        RadialGradient(
            colors: [flame.opacity(opacity), garnet.opacity(opacity * 0.35), .clear],
            center: .center, startRadius: 0, endRadius: 220
        )
    }

    // MARK: - Type

    /// Headlines are set in New York, the system serif. Everything else is San Francisco.
    /// Both come from text styles, so every word follows the Dynamic Type setting.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    // MARK: - Spacing, on a four-point grid

    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let snug: CGFloat = 12
        static let normal: CGFloat = 16
        static let roomy: CGFloat = 24
        static let wide: CGFloat = 32
    }

    // MARK: - Corners

    enum Radius {
        static let chip: CGFloat = 12
        static let card: CGFloat = 22
        static let sheet: CGFloat = 28
    }

    /// The smallest side of anything that can be tapped, from Apple's guidelines.
    static let tapTarget: CGFloat = 44

    // MARK: - Motion

    enum Motion {
        /// A state changing: the orb, a status line.
        static let state = Animation.smooth(duration: 0.35)
        /// Something answering a touch.
        static let touch = Animation.snappy(duration: 0.2)
        /// A screen or card arriving.
        static let arrive = Animation.spring(response: 0.5, dampingFraction: 0.85)
    }
}

// MARK: - Surfaces

private struct CardSurface: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

private struct FloatingGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    /// A solid card. Content sits on solid ground; glass is kept for things that float.
    func card(padding: CGFloat = Theme.Space.normal) -> some View {
        modifier(CardSurface(padding: padding))
    }

    /// Liquid Glass on iOS 26, the system material before it. For a control that floats
    /// over content, never for the content itself.
    func floatingGlass(in shape: some Shape = Capsule()) -> some View {
        modifier(FloatingGlass(shape: shape))
    }
}

// MARK: - Buttons

/// The one main action on a screen: a filled ember button with dark words.
struct EmberButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onFire)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Space.roomy)
            .background(Theme.buttonGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Theme.Motion.touch, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A second choice beside the main one: the same size, on quiet ground.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.emberInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Theme.Space.roomy)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .animation(Theme.Motion.touch, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == EmberButtonStyle {
    static var ember: EmberButtonStyle { EmberButtonStyle() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    static var quiet: QuietButtonStyle { QuietButtonStyle() }
}
