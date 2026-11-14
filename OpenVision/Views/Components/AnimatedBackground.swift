// OpenVision - AnimatedBackground.swift
// Beautiful animated gradient background

import SwiftUI

/// Animated gradient background for the app
struct AnimatedBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            // Near-black base
            Theme.bg

            // Emerald ambient glow — brightest around the center, drifting slowly for life.
            GeometryReader { geometry in
                ZStack {
                    // Main center glow (sits behind the orb)
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.accent.opacity(0.28), Theme.accentDeep.opacity(0.12), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.55
                            )
                        )
                        .frame(width: geometry.size.width * 1.2)
                        .offset(
                            x: animateGradient ? geometry.size.width * 0.06 : -geometry.size.width * 0.06,
                            y: animateGradient ? -geometry.size.height * 0.04 : geometry.size.height * 0.02
                        )
                        .blur(radius: 70)

                    // Subtle top glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.glow.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: geometry.size.width * 0.4
                            )
                        )
                        .frame(width: geometry.size.width * 0.8)
                        .offset(x: 0, y: -geometry.size.height * (animateGradient ? 0.34 : 0.30))
                        .blur(radius: 60)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 8)
                .repeatForever(autoreverses: true)
            ) {
                animateGradient = true
            }
        }
    }
}

/// Slow drifting motes behind the voice screen.
///
/// Each mote's position is a pure function of the clock, so no state changes per frame and
/// the drawing stops when the view goes away, when the app is in the background, and when
/// Reduce Motion is on.
struct ParticleEffect: View {
    let particleCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var particles: [Particle] = []

    struct Particle {
        var x: Double
        /// Where in its climb the mote starts, 0 to 1.
        var phase: Double
        var size: Double
        var opacity: Double
        /// Fraction of the view's height climbed per second.
        var speed: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    let climbed = (particle.phase + seconds * particle.speed).truncatingRemainder(dividingBy: 1)
                    let rect = CGRect(
                        x: particle.x * size.width,
                        y: (1 - climbed) * size.height,
                        width: particle.size,
                        height: particle.size
                    )
                    context.fill(Circle().path(in: rect), with: .color(.white.opacity(particle.opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if particles.count != particleCount { particles = Self.scatter(particleCount) }
        }
    }

    private static func scatter(_ count: Int) -> [Particle] {
        (0..<max(0, count)).map { _ in
            Particle(
                x: .random(in: 0...1),
                phase: .random(in: 0...1),
                size: .random(in: 1...3),
                opacity: .random(in: 0.1...0.3),
                speed: .random(in: 0.002...0.01)
            )
        }
    }
}

#Preview {
    ZStack {
        AnimatedBackground()

        ParticleEffect(particleCount: 50)

        VStack {
            Text("Phoenix Fox")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text("Beautiful Background")
                .foregroundColor(.white.opacity(0.7))
        }
    }
    .preferredColorScheme(.dark)
}
