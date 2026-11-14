// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// Guideline 5.1.1 / 5.1.2(i): consent per provider, revoke, delete all data, feature flags.
struct PrivacyAndDataView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var confirmErase = false
    @State private var consentProvider: CloudAIProvider?
    @State private var flagRefresh = UUID()

    var body: some View {
        Form {
            Section {
                NavigationLink("Privacy policy") {
                    LegalDocumentView(
                        title: "Privacy Policy",
                        url: StoreCatalog.privacyURL,
                        fallback: LegalCopy.privacySummary
                    )
                }
                NavigationLink("Terms of use") {
                    LegalDocumentView(
                        title: "Terms of Use",
                        url: StoreCatalog.termsURL,
                        fallback: LegalCopy.termsSummary
                    )
                }
            } header: {
                Text("Policy")
            } footer: {
                Text("Hosted URLs are configured in StoreCatalog. Until hosting is live, the in-app summary is shown.")
            }

            Section {
                ForEach(CloudAIProvider.allCases) { provider in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            if let when = CloudAIConsent.acceptedAt(provider) {
                                Text("Allowed \(when.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Not allowed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if CloudAIConsent.isAccepted(provider) {
                            Button("Withdraw", role: .destructive) {
                                CloudAIConsent.withdraw(provider)
                            }
                            .buttonStyle(.borderless)
                        } else {
                            Button("Allow") {
                                consentProvider = provider
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("Cloud AI data sharing")
            } footer: {
                Text("Required before prompts, photos, or memories leave this iPhone (App Store 5.1.2(i)).")
            }

            Section {
                Button("Delete all my data", role: .destructive) {
                    confirmErase = true
                }
            } header: {
                Text("Deletion")
            } footer: {
                Text("Wipes conversation history, memories, face prints, workshop data, API keys, OAuth tokens, and model caches on this iPhone. There is no Phoenix Fox cloud account.")
            }

            if BuildFlavor.current == .owner {
                Section {
                    ForEach(PrivacyFeatureFlag.allCases, id: \.rawValue) { flag in
                        Toggle(flag.displayName, isOn: Binding(
                            get: { flag.isEnabled() },
                            set: { flag.setEnabled($0); flagRefresh = UUID() }
                        ))
                    }
                } header: {
                    Text("Feature flags (owner)")
                } footer: {
                    Text("Conservative defaults for store builds. Meta DAT telemetry also needs Info.plist OptOut flipped when enabled.")
                        .id(flagRefresh)
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .sheet(item: $consentProvider) { provider in
            CloudAIConsentSheet(provider: provider) {
                consentProvider = nil
            } onDecline: {
                consentProvider = nil
            }
        }
        .confirmationDialog(
            "Delete all my data on this phone?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                DataDeletion.eraseAllOnThisPhone()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

struct CloudAIConsentSheet: View {
    let provider: CloudAIProvider
    var liveMode: Bool = false
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(CloudAIConsent.promptTitle(for: provider))
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                ScrollView {
                    Text(CloudAIConsent.promptBody(for: provider, liveMode: liveMode))
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Link("Privacy Policy", destination: StoreCatalog.privacyURL)
                if let url = provider.privacyPolicyURL {
                    Link("\(provider.shortName) Privacy Policy", destination: url)
                }
                Button {
                    CloudAIConsent.accept(provider)
                    onAccept()
                } label: {
                    Text("Allow")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Allow")
                Button("Not now, stay on this iPhone", role: .cancel) {
                    onDecline()
                }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Not now, stay on this iPhone")
            }
            .padding()
            .navigationTitle("Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

struct LegalDocumentView: View {
    let title: String
    let url: URL
    let fallback: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(fallback)
                    .font(.body)
                Link("Open on the web", destination: url)
                    .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle(title)
    }
}

enum LegalCopy {
    static let privacySummary = """
    Phoenix Fox keeps most data on this iPhone. Cloud AI providers you choose receive what you say, recent conversation, memories, and photos you ask Jarvis to look at — only after you Allow that provider in Privacy & Data. Face prints and the medication log never leave the phone. There is no Phoenix Fox account. Delete all my data clears local stores. Full policy: the web link below (hosting pending attorney review).
    """

    static let termsSummary = """
    Phoenix Fox is an independent app. It is not affiliated with Meta, Ray-Ban, Oakley, OpenAI, xAI, Google, or Marvel. You must be 18 or older. Cloud AI answers can be wrong. Do not use the app for covert recording or surveillance. Full terms: the web link below (hosting pending attorney review).
    """
}

#Preview {
    NavigationStack {
        PrivacyAndDataView()
            .environmentObject(SettingsManager.shared)
    }
}
