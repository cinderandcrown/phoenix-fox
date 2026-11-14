// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

/// Guideline 5.1.1 / 5.1.2(i): privacy policy, cloud AI consent, local erase, report, App Review demo.
struct PrivacyAndDataView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var reviewerDemo = ReviewerDemo.isEnabled()
    @State private var consentAccepted = CloudAIConsent.isAccepted()
    @State private var confirmErase = false
    @State private var showConsentSheet = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(PrivacyPolicyDocument.title)
                                .font(.title2.weight(.semibold))
                            Text(PrivacyPolicyDocument.effective)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(PrivacyPolicyDocument.body)
                                .font(.body)
                        }
                        .padding()
                    }
                    .navigationTitle("Privacy Policy")
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised.fill")
                }

                if let url = StoreCatalog.privacyURL {
                    Link(destination: url) {
                        Label("Privacy policy on the web", systemImage: "safari")
                    }
                }
            } header: {
                Text("Policy")
            } footer: {
                Text("Cinder & Crown does not create a Phoenix Fox cloud account. Optional cloud AI uses keys you provide.")
            }

            Section {
                if consentAccepted {
                    Label("Cloud AI sharing accepted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let when = CloudAIConsent.acceptedAt() {
                        Text("Accepted \(when.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Withdraw cloud AI consent", role: .destructive) {
                        CloudAIConsent.withdraw()
                        consentAccepted = false
                    }
                } else {
                    Button("Review cloud AI data sharing") {
                        showConsentSheet = true
                    }
                }
            } header: {
                Text("Cloud AI (5.1.2)")
            } footer: {
                Text(CloudAIConsent.promptBody)
            }

            Section {
                Toggle(isOn: $reviewerDemo) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Review demo")
                        Text("Phone mic and speaker; scripted answers; no glasses")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: reviewerDemo) { _, on in
                    ReviewerDemo.setEnabled(on)
                }
            } header: {
                Text("App Review")
            } footer: {
                Text("Turn this on for App Store review without hardware. See docs/APP_STORE_REVIEW_NOTES.md.")
            }

            Section {
                Button("Report a concern") {
                    let address = "privacy@cinderandcrown.com"
                    let subject = "Phoenix Fox concern"
                    let body = "Describe the AI reply or privacy issue:\n\n"
                    var comps = URLComponents()
                    comps.scheme = "mailto"
                    comps.path = address
                    comps.queryItems = [
                        URLQueryItem(name: "subject", value: subject),
                        URLQueryItem(name: "body", value: body)
                    ]
                    if let url = comps.url {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("For harmful AI output or a privacy issue. There is no public feed; this reaches the publisher.")
            }

            Section {
                Button("Erase all data on this phone", role: .destructive) {
                    confirmErase = true
                }
            } header: {
                Text("Deletion")
            } footer: {
                Text("There is no Phoenix Fox cloud account to delete. This resets settings and local stores on this iPhone. Sign out of SuperGrok or ChatGPT on their settings screens if you used those.")
            }
        }
        .navigationTitle("Privacy & Data")
        .onAppear {
            reviewerDemo = ReviewerDemo.isEnabled()
            consentAccepted = CloudAIConsent.isAccepted()
        }
        .sheet(isPresented: $showConsentSheet) {
            CloudAIConsentSheet {
                consentAccepted = true
                showConsentSheet = false
            } onDecline: {
                showConsentSheet = false
            }
        }
        .confirmationDialog(
            "Erase all data on this phone?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button("Erase", role: .destructive) {
                CloudAIConsent.withdraw()
                ReviewerDemo.setEnabled(false)
                settingsManager.resetToDefaults()
                consentAccepted = false
                reviewerDemo = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("API keys in the Keychain, settings, and local notes managed by Settings will be cleared. This cannot be undone.")
        }
    }
}

struct CloudAIConsentSheet: View {
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(CloudAIConsent.promptTitle)
                    .font(.title2.weight(.semibold))
                Text(CloudAIConsent.promptBody)
                    .font(.body)
                Spacer()
                Button {
                    CloudAIConsent.accept()
                    onAccept()
                } label: {
                    Text("I agree — send my prompts to the cloud AI I choose")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Not now — use on-device only", role: .cancel) {
                    onDecline()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("Consent")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        PrivacyAndDataView()
            .environmentObject(SettingsManager.shared)
    }
}
