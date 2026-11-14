// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Phoenix Fox - relay address, token, and the four assistants.

import SwiftUI

struct OwnAssistantSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var url = SettingsManager.shared.settings.relayURL
    @State private var token = SettingsManager.shared.settings.relayToken

    var body: some View {
        Form {
            Section {
                TextField("https://relay.example.com", text: $url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Relay token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Relay")
            } footer: {
                Text("The token stays in the Keychain. Short questions use Grok when a key is saved. Tasks go to Fire Fox, Indy, Driver, or Rally.")
            }

            Section {
                Toggle("Fast answers on Grok", isOn: $settingsManager.settings.jarvisFastMode)
                TextField("Wake word", text: $settingsManager.settings.wakeWord)
            } header: {
                Text("Voice")
            } footer: {
                Text("The app is Phoenix Fox. Jarvis is only the wake word.")
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
        .onDisappear {
            settingsManager.settings.relayURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            settingsManager.settings.relayToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
