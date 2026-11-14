// OpenVision - AIBackendSettingsView.swift
// AI backend selection and configuration

import SwiftUI

struct AIBackendSettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager

    // MARK: - Body

    var body: some View {
        Form {
            // Backend Selection
            Section {
                ForEach(AIBackendType.allCases, id: \.self) { backend in
                    Button {
                        settingsManager.settings.aiBackend = backend
                    } label: {
                        HStack {
                            Image(systemName: backend.icon)
                                .foregroundColor(Theme.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(backend.displayName)
                                    .foregroundColor(.primary)
                                Text(backend.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if settingsManager.settings.aiBackend == backend {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Choose Your AI")
            } footer: {
                Text("OpenClaw offers more tools and privacy. Gemini Live has lower latency.")
            }

            Section {
                let catalog = ProviderModelCatalogStore.load()
                ForEach(AIProviderID.allCases, id: \.self) { provider in
                    if let entry = catalog.entry(for: provider) {
                        NavigationLink {
                            providerSettings(provider)
                        } label: {
                            HStack {
                                Label(entry.displayName, systemImage: provider == .grok ? "bolt" : "sparkles")
                                Spacer()
                                if provider == .grok {
                                    Text("Default")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                configurationBadge(configured: settingsManager.settings.isProviderKeyConfigured(provider))
                            }
                        }
                    }
                }
            } header: {
                Text("Cloud providers")
            } footer: {
                Text("Grok is the default. Swap Claude, ChatGPT, or Gemini without changing app logic — model ids live in the catalog.")
            }

            Section {
                ForEach(Array(settingsManager.settings.resolvedProviderFallback.order.enumerated()), id: \.offset) { index, step in
                    Text("\(index + 1). \(fallbackTitle(step))")
                }
                Button("Reset to catalog (Grok → Claude → OpenAI → on-device)") {
                    settingsManager.settings.providerFallbackOrder = []
                }
            } header: {
                Text("Fallback order")
            } footer: {
                Text("Used when a provider errors or cannot handle vision. The relay (Fire Fox / Indy / Driver / Rally) is a separate assistant route, not a model provider.")
            }

            Section {
                let usage = settingsManager.settings.providerUsage
                LabeledContent("This month (est.)", value: String(format: "$%.2f", usage.totalDollars))
                Stepper(
                    "Soft cap: \(usage.monthlySoftCapDollars == 0 ? "Off" : "$\(usage.monthlySoftCapDollars)")",
                    value: $settingsManager.settings.providerUsage.monthlySoftCapDollars,
                    in: 0...500,
                    step: 5
                )
                if usage.softCapReached {
                    Text("Soft cap reached. Jarvis still answers; expensive top models stay available — this is a warning only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Provider usage")
            } footer: {
                Text("Estimates only. Soft cap never blocks a look or downgrades vision quality. Presence stays on-device-first.")
            }

            // Backend Configuration Links
            Section {
                NavigationLink {
                    OpenClawSettingsView()
                } label: {
                    HStack {
                        Label("OpenClaw Settings", systemImage: "terminal")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isOpenClawConfigured)
                    }
                }

                NavigationLink {
                    GeminiSettingsView()
                } label: {
                    HStack {
                        Label("Gemini Settings", systemImage: "waveform")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isGeminiConfigured)
                    }
                }

                NavigationLink {
                    OpenAISettingsView()
                } label: {
                    HStack {
                        Label("OpenAI Settings", systemImage: "sparkles")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isOpenAIConfigured)
                    }
                }

                NavigationLink {
                    OwnAssistantSettingsView()
                } label: {
                    HStack {
                        Label("Assistants", systemImage: "person.2")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isOwnAssistantConfigured)
                    }
                }

                NavigationLink {
                    HermesSettingsView()
                } label: {
                    HStack {
                        Label("Hermes Settings", systemImage: "server.rack")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isHermesConfigured)
                    }
                }

                NavigationLink {
                    AppleIntelligenceSettingsView()
                } label: {
                    HStack {
                        Label("Apple Intelligence", systemImage: "apple.logo")
                        Spacer()
                        configurationBadge(configured: AppleFoundationService.shared.isAvailable)
                    }
                }

                NavigationLink {
                    GemmaSettingsView()
                } label: {
                    HStack {
                        Label("Local Models", systemImage: "cpu")
                        Spacer()
                        configurationBadge(configured: settingsManager.settings.isLocalGemmaConfigured)
                    }
                }
            } header: {
                Text("Configuration")
            }
        }
        .navigationTitle("AI Backend")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func providerSettings(_ provider: AIProviderID) -> some View {
        switch provider {
        case .grok: GrokSettingsView()
        case .openAI: OpenAISettingsView()
        case .anthropic: ClaudeSettingsView()
        case .gemini: GeminiSettingsView()
        }
    }

    private func fallbackTitle(_ step: ProviderModelCatalog.FallbackStep) -> String {
        switch step {
        case .provider(let id): return id.displayName
        case .onDevice: return "On-device (Apple Intelligence / local)"
        }
    }

    @ViewBuilder
    private func configurationBadge(configured: Bool) -> some View {
        if configured {
            HStack(spacing: 4) {
                Text("Configured")
                    .font(.caption)
                    .foregroundColor(.green)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        } else {
            HStack(spacing: 4) {
                Text("Not configured")
                    .font(.caption)
                    .foregroundColor(.orange)
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AIBackendSettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
