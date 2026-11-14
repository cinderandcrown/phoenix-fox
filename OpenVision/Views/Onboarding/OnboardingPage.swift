// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// The layout every first-run step shares: where you are, what this step is, what it needs,
/// and one main button at the bottom where a thumb rests.
///
/// It takes plain values and closures, so a step can be previewed and snapshot-tested
/// without glasses or permissions.
struct OnboardingPage<Detail: View>: View {
    let step: OnboardingStep
    let primaryTitle: String
    let isBusy: Bool
    let onPrimary: () -> Void
    let onSkip: (() -> Void)?
    let onBack: (() -> Void)?
    let detail: Detail

    /// VoiceOver starts each step at its title, so the step is heard before its buttons.
    @AccessibilityFocusState private var titleFocused: Bool

    init(
        step: OnboardingStep,
        primaryTitle: String,
        isBusy: Bool = false,
        onPrimary: @escaping () -> Void,
        onSkip: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        @ViewBuilder detail: () -> Detail
    ) {
        self.step = step
        self.primaryTitle = primaryTitle
        self.isBusy = isBusy
        self.onPrimary = onPrimary
        self.onSkip = onSkip
        self.onBack = onBack
        self.detail = detail()
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.normal) {
                    hero
                        .padding(.top, Theme.Space.tight)

                    Text(step.title)
                        .font(Theme.display(.largeTitle, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)

                    Text(step.summary)
                        .font(.body)
                        .foregroundStyle(Theme.inkSoft)

                    detail

                    if let promise = step.promise {
                        Label(promise, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.top, Theme.Space.hair)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Theme.Space.roomy)
                .padding(.bottom, Theme.Space.roomy)
            }

            buttons
        }
        .background(HomeBackdrop())
        .onAppear { titleFocused = true }
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(minHeight: Theme.tapTarget)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Theme.emberInk)
            }
            Spacer()
            Text(step.progress)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.inkFaint)
                .frame(minHeight: Theme.tapTarget)
        }
        .padding(.horizontal, Theme.Space.roomy)
    }

    @ViewBuilder private var hero: some View {
        if step == .welcome {
            FoxMark()
                .frame(width: 96, height: 96)
        } else {
            Image(systemName: step.symbol)
                .font(.system(.title, weight: .semibold))
                .foregroundStyle(Theme.onFire)
                .frame(width: 64, height: 64)
                .background(Theme.buttonGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Space.hair) {
            Button(action: onPrimary) {
                HStack(spacing: Theme.Space.tight) {
                    if isBusy {
                        ProgressView().tint(Theme.onFire)
                    }
                    Text(primaryTitle)
                }
            }
            .buttonStyle(.ember)
            .disabled(isBusy)

            if let onSkip, let title = step.skipTitle {
                Button(title, action: onSkip)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.emberInk)
                    .frame(minHeight: Theme.tapTarget)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Theme.Space.roomy)
        .padding(.top, Theme.Space.snug)
        .padding(.bottom, Theme.Space.tight)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

// MARK: - Pieces the steps are built from

/// A symbol, a short heading, and a sentence. The welcome step lists three.
struct OnboardingPoint: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.snug) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.emberInk)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One permission: what it is, why it is asked for, and what the wearer has answered.
struct PermissionRow: View {
    let permission: OnboardingPermission
    let answer: PermissionAnswer
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack(alignment: .top, spacing: Theme.Space.snug) {
                Image(systemName: permission.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.emberInk)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(permission.reason)
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                    if let status = permission.status(answer) {
                        Label(status, systemImage: answer == .allowed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(answer == .allowed ? Theme.good : Theme.goldInk)
                            .padding(.top, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(permission.spoken(answer))

            if answer == .denied {
                Button("Open Settings", action: onOpenSettings)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.emberInk)
                    .frame(minHeight: Theme.tapTarget)
                    .padding(.leading, 32 + Theme.Space.snug)
                    .accessibilityHint("Opens the Settings app, where \(permission.title.lowercased()) can be turned on.")
            }
        }
        .card()
    }
}

/// A line of the last step's checklist.
struct ChecklistRow: View {
    let line: OnboardingSummary.Line

    var body: some View {
        Label {
            Text(line.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: line.done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(line.done ? Theme.good : Theme.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.done ? "Done" : "Not yet"). \(line.text)")
    }
}

/// The outcome of something the wearer just tried: connected, or what went wrong.
struct OutcomeLabel: View {
    let text: String
    let good: Bool

    var body: some View {
        Label(text, systemImage: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(good ? Theme.good : Theme.goldInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Samples and previews

#if DEBUG
/// Each step as it looks part-way through setting up, for previews and snapshot tests.
/// Debug builds only.
enum OnboardingSamples {
    static let summary = OnboardingSummary(
        glassesConnected: false, microphone: .allowed, speech: .allowed, brain: .onDevice, wakeWord: "Jarvis"
    )

    @MainActor @ViewBuilder
    static func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:
            OnboardingPage(step: step, primaryTitle: "Get started", onPrimary: {}) {
                WelcomePoints()
            }
        case .glasses:
            OnboardingPage(step: step, primaryTitle: OnboardingStep.glassesButton(connected: false, stall: nil), onPrimary: {}, onSkip: {}, onBack: {}) {
                GlassesStepDetail(connected: false, stall: nil, details: "")
            }
        case .permissions:
            OnboardingPage(step: step, primaryTitle: "Continue", onPrimary: {}, onBack: {}) {
                PermissionRow(permission: .microphone, answer: .allowed, onOpenSettings: {})
                PermissionRow(permission: .speech, answer: .denied, onOpenSettings: {})
                PermissionRow(permission: .notifications, answer: .notAsked, onOpenSettings: {})
            }
        case .assistants:
            OnboardingPage(step: step, primaryTitle: "Connect", onPrimary: {}, onSkip: {}, onBack: {}) {
                RelayFields(address: .constant(""), token: .constant(""))
                OutcomeLabel(text: "Enter the relay token first.", good: false)
            }
        case .ready:
            OnboardingPage(step: step, primaryTitle: "Start", onPrimary: {}, onBack: {}) {
                ReadyChecklist(summary: summary)
            }
        }
    }

    /// The glasses step after the wearer came back from Meta AI and nothing was connected.
    @MainActor
    static var glassesTrouble: some View {
        let stall = RegistrationStall.returnedUnconnected
        let attempt = RegistrationAttempt()
        return OnboardingPage(
            step: .glasses,
            primaryTitle: OnboardingStep.glassesButton(connected: false, stall: stall),
            onPrimary: {},
            onSkip: {},
            onBack: {}
        ) {
            GlassesStepDetail(connected: false, stall: stall, details: attempt.details(stage: .available))
        }
    }
}

#Preview("Welcome") {
    OnboardingSamples.page(.welcome)
}

#Preview("Glasses") {
    OnboardingSamples.page(.glasses)
}

#Preview("Permissions, one denied, light") {
    OnboardingSamples.page(.permissions)
        .preferredColorScheme(.light)
}

#Preview("Assistants") {
    OnboardingSamples.page(.assistants)
}

#Preview("Ready, largest type") {
    OnboardingSamples.page(.ready)
        .dynamicTypeSize(.accessibility5)
}
#endif
