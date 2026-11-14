// OpenVision - SettingsView.swift
// Main settings menu with navigation to configuration panels

import SwiftUI

struct SettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var glassesManager: GlassesManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        PhoenixLogView()
                    } label: {
                        Label("Task history and notes", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        SmartCaptureSettingsView()
                    } label: {
                        Label("Smart Capture", systemImage: "camera.viewfinder")
                    }
                    NavigationLink {
                        AccessibilitySettingsView()
                    } label: {
                        Label("Accessibility", systemImage: "accessibility")
                    }
                } header: {
                    Text("Phoenix Fox")
                }

                if BuildFlavor.current == .owner {
                    Section {
                        NavigationLink {
                            GlassesLimitsView()
                        } label: {
                            Label("Glasses limits", systemImage: "slider.horizontal.3")
                        }
                        NavigationLink {
                            WorkshopSettingsView()
                        } label: {
                            Label("Workshop", systemImage: "hammer")
                        }
                        Button {
                            settingsManager.applyOwnerProfile()
                        } label: {
                            Label("Turn everything on again", systemImage: "sparkles")
                        }
                    } header: {
                        Text("Owner build")
                    } footer: {
                        Text("Every feature starts switched on in this build: the accessibility suite, Guide mode, Smart Capture, memory, the bot team, the experimental glasses features, and the workshop. Anything you switch off stays off until you use this button. Nothing starts the camera or a recording by itself, and Guide mode still reads its safety notice first.")
                    }
                }

                // AI Backend Section
                Section {
                    NavigationLink {
                        AIBackendSettingsView()
                    } label: {
                        HStack {
                            Label("AI Backend", systemImage: "cpu")
                            Spacer()
                            Text(settingsManager.settings.aiBackend.displayName)
                                .foregroundColor(.secondary)
                            if !settingsManager.settings.isCurrentBackendConfigured {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    NavigationLink {
                        WebSearchSettingsView()
                    } label: {
                        HStack {
                            Label("Web Search", systemImage: "magnifyingglass")
                            Spacer()
                            Text(settingsManager.settings.tavilyAPIKey.isEmpty ? "DuckDuckGo" : "Tavily")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Only show for Gemini Live (OpenClaw has its own system prompt & memories)
                    if settingsManager.settings.aiBackend == .geminiLive {
                        NavigationLink {
                            AdditionalInstructionsView()
                        } label: {
                            Label("Custom Instructions", systemImage: "text.quote")
                        }

                        NavigationLink {
                            MemoriesView()
                        } label: {
                            HStack {
                                Label("Memories", systemImage: "brain")
                                Spacer()
                                Text("\(settingsManager.settings.memories.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("AI")
                }

                // Hardware Section
                Section {
                    NavigationLink {
                        GlassesSettingsView()
                    } label: {
                        HStack {
                            Label("Glasses", systemImage: "eyeglasses")
                            Spacer()
                            if glassesManager.isRegistered {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Hardware")
                }

                // Voice Section
                Section {
                    NavigationLink {
                        VoiceSettingsView()
                    } label: {
                        HStack {
                            Label("Voice Control", systemImage: "mic.fill")
                            Spacer()
                            if settingsManager.settings.wakeWordEnabled {
                                Text(settingsManager.settings.wakeWord)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Off")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Voice")
                }

                // Advanced Section
                Section {
                    NavigationLink {
                        DocumentsSettingsView()
                    } label: {
                        Label("My Documents", systemImage: "books.vertical")
                    }

                    NavigationLink {
                        TelemetrySettingsView()
                    } label: {
                        Label("Telemetry", systemImage: "chart.line.uptrend.xyaxis")
                    }

                    Toggle(isOn: $settingsManager.settings.autoReconnect) {
                        Label("Auto-Reconnect", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Toggle(isOn: $settingsManager.settings.showTranscripts) {
                        Label("Show Transcripts", systemImage: "text.bubble")
                    }
                } header: {
                    Text("Advanced")
                }

                // About Section
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("\(Config.appVersion) (\(Config.buildNumber))")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com/rayl15/OpenVision")!) {
                        Label("GitHub Repository", systemImage: "link")
                    }

                    Link(destination: URL(string: "https://github.com/openclaw/openclaw")!) {
                        Label("Get OpenClaw", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Phoenix Fox is built on OpenVision, which is MIT licensed. Say Jarvis to wake it.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsManager.shared)
        .environmentObject(GlassesManager.shared)
}
