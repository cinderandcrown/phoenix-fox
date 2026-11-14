// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// The live orb: a coal that rests, listens, thinks, and speaks.
///
/// `EmberGeometry` works out the shape. This view draws it thirty times a second, and holds
/// it still when Reduce Motion is on or a fixed time is given. A red ring means the glasses
/// camera is on.
struct EmberOrb: View {
    let mood: OrbMood
    var seeing = false
    /// Holds the clock at this many seconds. Previews and snapshot tests use it so the
    /// same inputs always draw the same picture.
    var fixedTime: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previous: OrbMood? = nil
    @State private var changed = Date.distantPast
    @State private var born = Date()

    /// Seconds a change of mood takes.
    private static let changeTime = 0.45

    private var isStill: Bool { reduceMotion || fixedTime != nil }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill)) { timeline in
            let time = fixedTime ?? (reduceMotion ? 0 : timeline.date.timeIntervalSince(born))
            let progress = isStill ? 1 : timeline.date.timeIntervalSince(changed) / Self.changeTime
            let look = EmberGeometry.look(for: previous ?? mood)
                .mixed(with: EmberGeometry.look(for: mood), progress: progress)
            Canvas { context, size in
                EmberPainter.draw(&context, size: size, time: time, look: look)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if seeing {
                Circle()
                    .strokeBorder(Theme.seeing, lineWidth: 3)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.state, value: seeing)
        .onChange(of: mood) { old, _ in
            previous = old
            changed = Date()
        }
        .accessibilityHidden(true)
    }
}

/// Draws one frame of the orb. It is separate from the view so it can be called from the
/// canvas without touching any view state.
enum EmberPainter {
    static func draw(_ context: inout GraphicsContext, size: CGSize, time: Double, look: EmberGeometry.Look) {
        let side = min(size.width, size.height)
        guard side > 0 else { return }
        let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let heat = min(max(look.heat, 0), 1)

        func layer(_ index: Int, scale: Double) -> Path {
            path(EmberGeometry.outline(time: time, look: look, layer: index, scale: scale), in: rect)
        }

        // The glow: the same shape, blurred, behind everything.
        var glow = context
        glow.addFilter(.blur(radius: side * 0.07))
        glow.opacity = 0.30 + 0.40 * heat
        glow.fill(
            layer(0, scale: 0.94),
            with: .radialGradient(
                Gradient(colors: [Theme.ember, Theme.garnet]),
                center: center, startRadius: side * 0.10, endRadius: side * 0.50
            )
        )

        // The body of the coal.
        var body = context
        body.opacity = 0.70 + 0.30 * heat
        body.fill(
            layer(1, scale: 0.84),
            with: .radialGradient(
                Gradient(colors: [Theme.flame, Theme.ember, Theme.garnet]),
                center: center, startRadius: 0, endRadius: side * 0.44
            )
        )

        // The core, which goes from gold toward white as it heats.
        let hot = Color(BrandPalette.ink.dark.over(BrandPalette.gold.dark, opacity: heat * 0.8))
        var core = context
        core.addFilter(.blur(radius: side * 0.02))
        core.opacity = 0.55 + 0.45 * heat
        core.fill(
            layer(2, scale: 0.50 + 0.08 * heat),
            with: .radialGradient(
                Gradient(colors: [hot, Theme.gold, Theme.flame]),
                center: center, startRadius: 0, endRadius: side * 0.30
            )
        )
    }

    /// A smooth closed path through points given in a unit square.
    static func path(_ points: [(x: Double, y: Double)], in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let placed = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: middle(placed[placed.count - 1], placed[0]))
        for index in placed.indices {
            path.addQuadCurve(to: middle(placed[index], placed[(index + 1) % placed.count]), control: placed[index])
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Orb, every mood") {
    ScrollView {
        VStack(spacing: Theme.Space.roomy) {
            ForEach(OrbMood.allCases, id: \.self) { mood in
                VStack {
                    EmberOrb(mood: mood, seeing: mood == .thinking)
                        .frame(width: 180, height: 180)
                    Text(mood.rawValue.capitalized)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    .background(Theme.canvas)
}
