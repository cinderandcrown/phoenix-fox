// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

// What the wearer sees around the button that opens the Meta AI app: what to do there
// first, and what to do when Meta AI did not connect the glasses. First run and the
// Glasses screen show the same words. The words and the rules are in GlassesRegistration.

/// A numbered list of things to do. VoiceOver reads each as "Step 2 of 3", and the text
/// wraps at any size.
struct NumberedSteps: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.tight) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.emberInk)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NumberedStep.spoken(index, of: steps))
            }
        }
    }
}

/// What to do in the Meta AI app before connecting, and why.
struct GlassesPreparationList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Text(GlassesPreparation.heading)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            NumberedSteps(steps: GlassesPreparation.steps)
            Text(GlassesPreparation.reason)
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What went wrong with a try at connecting, and what to do about it.
///
/// VoiceOver moves to the title when this appears, so someone who cannot see the screen
/// change hears that the try did not work before anything else.
struct RegistrationRecovery: View {
    let stall: RegistrationStall
    /// One line about the try, for whoever is helping.
    let details: String
    var isBusy = false
    /// Shown as a "Try again" button when the screen has no other button for it.
    var onRetry: (() -> Void)?

    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Label {
                Text(stall.title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.goldInk)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Problem. \(stall.title)")
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)

            Text(stall.explanation)
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            NumberedSteps(steps: stall.steps)

            if let onRetry, stall.canRetry {
                Button("Try again", action: onRetry)
                    .buttonStyle(.quiet)
                    .disabled(isBusy)
                    .accessibilityHint("Opens the Meta AI app again.")
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel("Details for support. \(details)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { titleFocused = true }
    }
}

/// The middle of first run's glasses step: connected, what went wrong, or what to do first.
struct GlassesStepDetail: View {
    let connected: Bool
    let stall: RegistrationStall?
    let details: String

    var body: some View {
        if connected {
            OutcomeLabel(text: "Your glasses are connected.", good: true)
        } else if let stall {
            RegistrationRecovery(stall: stall, details: details)
                .card()
        } else {
            GlassesPreparationList()
                .card()
        }
    }
}

#if DEBUG
#Preview("Before connecting") {
    OnboardingSamples.page(.glasses)
}

#Preview("Meta AI refused, largest type") {
    OnboardingSamples.glassesTrouble
        .dynamicTypeSize(.accessibility5)
}
#endif
