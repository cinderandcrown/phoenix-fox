// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// First run, connected to the running app.
//
// Five steps, one at a time, each with a button to go on and a way to skip. `OnboardingFlow`
// holds the words and the rules. `OnboardingPage` is the layout. This file asks iOS and the
// Meta AI app for what each step needs and remembers how far the wearer got.

import AVFoundation
import Speech
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var glassesManager: GlassesManager

    /// How far the wearer got, so leaving for the Meta AI app or the Settings app and
    /// coming back does not start over.
    @AppStorage("onboardingStep") private var savedStep = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var answers: [OnboardingPermission: PermissionAnswer] = [:]
    @State private var isBusy = false

    @State private var relayAddress = ""
    @State private var relayToken = ""
    @State private var relayOutcome: RelayCheck.Outcome?

    private var step: OnboardingStep { OnboardingStep.restored(savedStep) }

    var body: some View {
        ZStack {
            // A cross-fade, forward or back. It reads the same with Reduce Motion on.
            page
                .transition(.opacity)
                .id(step)
        }
        .onAppear {
            relayAddress = settingsManager.settings.relayURL
            relayToken = settingsManager.settings.relayToken
        }
        .task { await readAnswers() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the Settings app: an answer may have changed there.
            if phase == .active { Task { await readAnswers() } }
        }
    }

    // MARK: - Steps

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            OnboardingPage(step: step, primaryTitle: "Get started", onPrimary: { goOn() }) {
                WelcomePoints()
            }

        case .glasses:
            OnboardingPage(
                step: step,
                primaryTitle: OnboardingStep.glassesButton(
                    connected: glassesManager.isRegistered,
                    stall: glassesManager.registration.stall
                ),
                isBusy: glassesManager.registration.isWorking,
                onPrimary: { glassesManager.isRegistered ? goOn() : connectGlasses() },
                onSkip: glassesManager.isRegistered ? nil : { goOn() },
                onBack: { goBack() }
            ) {
                GlassesStepDetail(
                    connected: glassesManager.isRegistered,
                    stall: glassesManager.registration.stall,
                    details: glassesManager.registrationDetails
                )
            }

        case .permissions:
            OnboardingPage(
                step: step,
                primaryTitle: hasUnasked ? "Allow" : "Continue",
                isBusy: isBusy,
                onPrimary: { hasUnasked ? askAll() : goOn() },
                onSkip: hasUnasked ? { goOn() } : nil,
                onBack: { goBack() }
            ) {
                ForEach(OnboardingPermission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission, answer: answer(permission), onOpenSettings: { openSettings() })
                }
            }

        case .assistants:
            OnboardingPage(
                step: step,
                primaryTitle: relayOutcome?.isGood == true ? "Continue" : "Connect",
                isBusy: isBusy,
                onPrimary: { relayOutcome?.isGood == true ? goOn() : connectRelay() },
                onSkip: relayOutcome?.isGood == true ? nil : { goOn() },
                onBack: { goBack() }
            ) {
                RelayFields(address: $relayAddress, token: $relayToken)
                    .onChange(of: relayAddress) { relayOutcome = nil }
                    .onChange(of: relayToken) { relayOutcome = nil }
                if let relayOutcome {
                    OutcomeLabel(text: relayOutcome.line, good: relayOutcome.isGood)
                }
            }

        case .ready:
            OnboardingPage(step: step, primaryTitle: "Start", onPrimary: { finish() }, onBack: { goBack() }) {
                ReadyChecklist(summary: summary)
            }
        }
    }

    // MARK: - Moving

    private func go(to next: OnboardingStep?) {
        guard let next else { return }
        withAnimation(Theme.Motion.arrive) { savedStep = next.rawValue }
    }

    private func goOn() { go(to: step.next) }
    private func goBack() { go(to: step.previous) }

    private func finish() {
        // Someone with nothing set up still gets an answer: the AI built into the phone.
        switch startingBrain {
        case .assistants:
            settingsManager.settings.aiBackend = .ownAssistant
        case .onDevice:
            settingsManager.settings.aiBackend = .appleFoundation
        case .keepCurrent, .none:
            break
        }
        savedStep = 0
        withAnimation(Theme.Motion.arrive) { hasCompletedOnboarding = true }
    }

    // MARK: - Glasses

    /// Opens Meta AI. How it went is in `glassesManager.registration`: Meta AI can refuse
    /// without an error reaching Phoenix Fox, so the manager judges the try when the
    /// wearer comes back, and this step shows what it found.
    private func connectGlasses() {
        Task { await glassesManager.register() }
    }

    // MARK: - Permissions

    private func answer(_ permission: OnboardingPermission) -> PermissionAnswer {
        answers[permission] ?? .notAsked
    }

    private var hasUnasked: Bool {
        OnboardingPermission.allCases.contains { answer($0) == .notAsked }
    }

    private func readAnswers() async {
        for permission in OnboardingPermission.allCases {
            answers[permission] = await SystemPermissions.answer(for: permission)
        }
    }

    /// Asks for each permission that has not been answered, one after another, in the
    /// order they are listed. Each reason is on the screen before its question appears.
    private func askAll() {
        isBusy = true
        Task {
            for permission in OnboardingPermission.allCases where answer(permission) == .notAsked {
                answers[permission] = await SystemPermissions.ask(for: permission)
            }
            isBusy = false
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    // MARK: - Assistants

    private func connectRelay() {
        isBusy = true
        Task {
            let result = await OwnAssistantService.shared.check(address: relayAddress, token: relayToken)
            let outcome = RelayCheck.describe(result, address: relayAddress)
            relayOutcome = outcome
            if outcome.isGood {
                settingsManager.settings.relayURL = relayAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsManager.settings.relayToken = relayToken.trimmingCharacters(in: .whitespacesAndNewlines)
                await OwnAssistantService.shared.registerDeviceIfNeeded()
            }
            isBusy = false
        }
    }

    // MARK: - The last step

    private var startingBrain: StartingBrain {
        let settings = settingsManager.settings
        let onDeviceReady = AppleFoundationService.shared.isAvailable
        return StartingBrain.choose(
            relayReady: settings.isOwnAssistantConfigured,
            currentIsAssistants: settings.aiBackend == .ownAssistant,
            currentReady: settings.aiBackend == .appleFoundation ? onDeviceReady : settings.isCurrentBackendConfigured,
            onDeviceReady: onDeviceReady
        )
    }

    private var summary: OnboardingSummary {
        OnboardingSummary(
            glassesConnected: glassesManager.isRegistered,
            microphone: answer(.microphone),
            speech: answer(.speech),
            brain: startingBrain,
            wakeWord: settingsManager.settings.wakeWord
        )
    }
}

// MARK: - Step details

struct WelcomePoints: View {
    var body: some View {
        VStack(spacing: Theme.Space.normal) {
            OnboardingPoint(symbol: "waveform", title: "Talk, hands-free", text: "Say “Jarvis” and ask. The answer is spoken in your glasses.")
            OnboardingPoint(symbol: "eye.fill", title: "Ask it to look", text: "Jarvis can see what you see, only when you ask. The capture light shows when.")
            OnboardingPoint(symbol: "person.3.fill", title: "Your team, at work", text: "Hand a task to one of your assistants by name and see what each is doing.")
        }
        .padding(.top, Theme.Space.tight)
    }
}

/// The relay's address and token.
struct RelayFields: View {
    @Binding var address: String
    @Binding var token: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text("Relay address")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                TextField("Relay address", text: $address, prompt: Text(RelayEndpoint.defaultAddress))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityHint("Leave empty to use the Phoenix Fox relay.")
            }
            Divider()
            VStack(alignment: .leading, spacing: Theme.Space.hair) {
                Text("Relay token")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                SecureField("Relay token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint("The token your relay was set up with.")
            }
        }
        .card()
    }
}

struct ReadyChecklist: View {
    let summary: OnboardingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.normal) {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                ForEach(summary.lines) { line in
                    ChecklistRow(line: line)
                }
            }
            .card()

            Text(summary.tryThis)
                .font(Theme.display(.title3))
                .foregroundStyle(Theme.ink)
        }
    }
}

// MARK: - Asking iOS

/// Reads and asks for the three permissions of first run.
@MainActor
enum SystemPermissions {
    static func answer(for permission: OnboardingPermission) async -> PermissionAnswer {
        switch permission {
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .allowed
            case .denied: return .denied
            case .undetermined: return .notAsked
            @unknown default: return .notAsked
            }
        case .speech:
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: return .allowed
            case .denied, .restricted: return .denied
            case .notDetermined: return .notAsked
            @unknown default: return .notAsked
            }
        case .notifications:
            switch await PushAlerts.status() {
            case .on: return .allowed
            case .off: return .denied
            case .notAsked: return .notAsked
            }
        }
    }

    static func ask(for permission: OnboardingPermission) async -> PermissionAnswer {
        switch permission {
        case .microphone:
            return await AVAudioApplication.requestRecordPermission() ? .allowed : .denied
        case .speech:
            return await VoiceCommandService.shared.requestAuthorization() ? .allowed : .denied
        case .notifications:
            return await PushAlerts.refresh(askIfNeeded: true) == .on ? .allowed : .denied
        }
    }
}
