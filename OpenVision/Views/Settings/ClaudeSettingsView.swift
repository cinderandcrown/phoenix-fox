// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

struct ClaudeSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = SettingsManager.shared.settings.claudeAPIKey
    @State private var model = SettingsManager.shared.settings.claudeModel
    @State private var testStatus: String?

    private var catalogChoices: [String] {
        ProviderModelCatalogStore.load().entry(for: .anthropic)?.modelChoices ?? [model]
    }

    var body: some View {
        Form {
            Section {
                SecureField("sk-ant-…", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                ProviderKeyTestButton(provider: .anthropic, apiKey: apiKey, status: $testStatus)
                if let testStatus {
                    Text(testStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("API key")
            } footer: {
                Text("Stored in this phone's Keychain. Never logged.")
            }

            Section {
                if catalogChoices.isEmpty {
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("Ids come from the bundled model catalog and can change without an App Store update.")
            }

            Section {
                Link(destination: URL(string: "https://console.anthropic.com/")!) {
                    HStack {
                        Text("Get API key")
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save(); dismiss() }
            }
        }
        .onDisappear { save() }
    }

    private var modelChoices: [String] {
        catalogChoices.contains(model) ? catalogChoices : [model] + catalogChoices
    }

    private func save() {
        settingsManager.settings.claudeAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.settings.claudeModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
