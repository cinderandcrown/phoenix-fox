// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - relay address, token, and the four assistants.

import SwiftUI
import UIKit

struct OwnAssistantSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var url = SettingsManager.shared.settings.relayURL
    @State private var token = SettingsManager.shared.settings.relayToken
    @State private var check: RelayCheck = .idle
    @State private var alerts: PushAlerts.Status?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                TextField("Relay address", text: $url, prompt: Text(RelayEndpoint.defaultAddress))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .accessibilityHint("Leave empty to use the Phoenix Fox relay.")
                SecureField("Relay token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityHint("The token your relay was set up with.")
            } header: {
                Text("Relay")
            } footer: {
                Text("Leave the address empty to use the Phoenix Fox relay. The token stays in this phone's Keychain. Short questions use Grok when a key is saved. Tasks go to Fire Fox, Indy, Driver, or Rally.")
            }

            Section {
                Button {
                    Task { await runCheck() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if check == .running { ProgressView() }
                    }
                }
                .disabled(check == .running || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let line = check.line {
                    Label(line, systemImage: check.isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(check.isGood ? Color.green : Color.orange)
                        .font(.footnote)
                        .accessibilityLabel(line)
                }
            }
            .onChange(of: url) { check = .idle }
            .onChange(of: token) { check = .idle }

            Section {
                if let alerts {
                    LabeledContent("Alerts", value: alerts.line)
                    switch alerts {
                    case .notAsked:
                        Button("Turn on alerts") {
                            Task { self.alerts = await PushAlerts.refresh(askIfNeeded: true) }
                        }
                    case .off:
                        Button("Open iOS Settings") {
                            if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                        }
                    case .on:
                        EmptyView()
                    }
                }
            } footer: {
                Text("An assistant can send you an alert, such as a finished task. iOS asks for permission when you turn this on. The alert only says something is waiting. The message is fetched from your relay.")
            }
            .task { alerts = await PushAlerts.status() }

            Section {
                Toggle("Fast answers on Grok", isOn: $settingsManager.settings.jarvisFastMode)
                Toggle("Short spoken replies", isOn: $settingsManager.settings.shortSpokenReplies)
                Toggle("Mind meld", isOn: $settingsManager.settings.mindMeldEnabled)
                TextField("Wake word", text: $settingsManager.settings.wakeWord)
            } header: {
                Text("Voice")
            } footer: {
                Text("The app is Phoenix Fox. Jarvis is only the wake word. With short spoken replies on, a long answer pauses after about half a minute. Say “go on” to hear the rest. The whole answer is always in History. Mind meld keeps what you say on this phone. It does not keep a photo unless you say remember, and the capture light is on for that shot.")
            }

            Section("Assistants") {
                ForEach(settingsManager.settings.assistantBots) { bot in
                    HStack {
                        Text(bot.name)
                        Spacer()
                        if bot.isDefault {
                            Text("Default").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Assistants")
        .onDisappear(perform: save)
    }

    private func save() {
        settingsManager.settings.relayURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.settings.relayToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        // The push token arrived at launch, before there was a relay to give it to.
        Task { await OwnAssistantService.shared.registerDeviceIfNeeded() }
    }

    private func runCheck() async {
        check = .running
        let result = await OwnAssistantService.shared.check(address: url, token: token)
        check = .finished(RelayCheck.describe(result, address: url))
        if case .finished(let outcome) = check {
            // Say the result, so it is not missed by someone who cannot see it appear.
            UIAccessibility.post(notification: .announcement, argument: outcome.line)
            if outcome.isGood { save() }
        }
    }
}

/// The state of the "Test connection" row.
enum RelayCheck: Equatable {
    struct Outcome: Equatable {
        var isGood: Bool
        var line: String
    }

    case idle
    case running
    case finished(Outcome)

    var line: String? {
        if case .finished(let outcome) = self { return outcome.line }
        return nil
    }

    var isGood: Bool {
        if case .finished(let outcome) = self { return outcome.isGood }
        return false
    }

    /// Turns the relay's answer into one sentence for the wearer.
    static func describe(_ result: Result<RelayHealth, RelayError>, address: String) -> Outcome {
        switch result {
        case .success(let health):
            var parts = ["Connected."]
            switch health.apns {
            case true?: parts.append("Push alerts are set up.")
            case false?: parts.append("Push alerts are not set up on the relay.")
            case nil: break
            }
            if !health.webhooks.isEmpty {
                parts.append("Webhooks: \(health.webhooks.joined(separator: ", ")).")
            }
            if !health.webhookProblems.isEmpty {
                parts.append("Webhook problems: \(health.webhookProblems.joined(separator: "; ")).")
            }
            return Outcome(isGood: true, line: parts.joined(separator: " "))
        case .failure(.notConfigured):
            let hasAddress = !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return Outcome(isGood: false, line: hasAddress
                ? "That address can't be used. It must start with https."
                : "Enter the relay token first.")
        case .failure(let error):
            return Outcome(isGood: false, line: error.localizedDescription)
        }
    }
}
