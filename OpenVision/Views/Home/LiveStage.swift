// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// The middle of the home screen: the orb, one word for what Jarvis is doing, and one line
/// of help. The whole thing is one button.
///
/// To VoiceOver it is a single element, "Jarvis", whose value is the phase and whose hint
/// is what a double tap does. The phase is not announced when it changes: the phone's
/// speaker would be heard by the microphone that is listening for the wake word. Sound
/// cues on the glasses and haptics on the phone mark the changes instead.
struct LiveStage: View {
    let phase: LivePhase
    let signals: LiveSignals
    var fixedTime: Double?
    let onTap: (StageTap) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let spoken = StageDescription(phase: phase, signals: signals)
        Button {
            onTap(phase.tap)
        } label: {
            VStack(spacing: Theme.Space.normal) {
                EmberOrb(mood: phase.mood, seeing: signals.cameraOn, fixedTime: fixedTime)
                    .frame(maxWidth: 232)
                    .padding(.horizontal, Theme.Space.wide)

                VStack(spacing: Theme.Space.hair) {
                    HStack(spacing: Theme.Space.tight) {
                        Image(systemName: phase.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.emberInk)
                            .symbolEffect(.pulse, options: .repeating, isActive: phase.isBusy && !reduceMotion && fixedTime == nil)
                        Text(phase.title)
                            .font(Theme.display(.title))
                            .foregroundStyle(Theme.ink)
                            .contentTransition(.opacity)
                    }
                    Text(phase.hint(signals))
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                        .contentTransition(.opacity)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(StageButtonStyle())
        .animation(Theme.Motion.state, value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken.label)
        .accessibilityValue(spoken.value)
        .accessibilityHint(spoken.hint)
        .accessibilityAddTraits([.isButton, .updatesFrequently])
    }
}

/// The orb gives a little under a finger. Nothing else about it changes.
private struct StageButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.touch, value: configuration.isPressed)
    }
}

#Preview("Stage, the four states") {
    ScrollView {
        VStack(spacing: Theme.Space.wide) {
            LiveStage(phase: .listening, signals: LiveSignals(activity: .listening)) { _ in }
            LiveStage(phase: .looking, signals: LiveSignals(activity: .thinking, cameraOn: true)) { _ in }
            LiveStage(phase: .asking("Indy"), signals: LiveSignals(activity: .thinking, askedAssistant: "Indy")) { _ in }
            LiveStage(phase: .replying, signals: LiveSignals(activity: .speaking)) { _ in }
        }
        .padding()
    }
    .background(Theme.canvas)
}

#Preview("Stage, at rest, light, largest type") {
    LiveStage(phase: .ready, signals: LiveSignals()) { _ in }
        .padding()
        .background(Theme.canvas)
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility5)
}
