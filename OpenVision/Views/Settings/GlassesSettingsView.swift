// OpenVision - GlassesSettingsView.swift
// Meta Ray-Ban glasses registration and status

import SwiftUI
import MWDATCore

struct GlassesSettingsView: View {
    // MARK: - Environment

    @EnvironmentObject var glassesManager: GlassesManager

    // MARK: - State

    @State private var showingUnregisterConfirmation: Bool = false
    @State private var showingReregisterConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        Form {
            // Registration Section
            Section {
                if glassesManager.isRegistered {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Registered")
                            .foregroundColor(.green)
                        Spacer()
                        Button("Unregister") {
                            showingUnregisterConfirmation = true
                        }
                        .foregroundColor(.red)
                        .font(.caption)
                    }

                    Button {
                        showingReregisterConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if glassesManager.pendingReregisterAfterUnregister
                                || glassesManager.registration.isWorking {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text(
                                    glassesManager.pendingReregisterAfterUnregister
                                        ? "Disconnecting, then Meta AI…"
                                        : "Opening Meta AI…"
                                )
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Disconnect & re-register")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        glassesManager.registration.isWorking
                            || glassesManager.pendingReregisterAfterUnregister
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Register with Meta AI app to access your glasses")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // The same steps first run shows. Meta AI refuses to connect
                        // until they are done and says only "Internal error".
                        GlassesPreparationList()

                        Button {
                            register()
                        } label: {
                            HStack {
                                Spacer()
                                if glassesManager.registration.isWorking {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                    Text("Opening Meta AI...")
                                } else {
                                    Image(systemName: "person.badge.plus")
                                    Text("Register App")
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(glassesManager.registration.isWorking)
                    }

                    if let stall = glassesManager.registration.stall {
                        RegistrationRecovery(
                            stall: stall,
                            details: glassesManager.registrationDetails,
                            isBusy: glassesManager.registration.isWorking,
                            onRetry: { register() }
                        )
                    }
                }
            } header: {
                Text("Registration")
            } footer: {
                Text("Register once. Do not tap Register on every launch (Meta DAT #177). If you turned on Developer Mode after registering and Phoenix Fox is missing under Meta AI → App connections → Developer mode apps, use Disconnect & re-register once. Real MetaAppID builds can still register as a Dev Mode app while Developer Mode is on (Meta #197); for the production-like path turn Developer Mode off and use a Wearables Developer Center release-channel invite.")
            }

            // Device Status Section
            if glassesManager.isRegistered {
                Section {
                    HStack {
                        Text("Connected Devices")
                        Spacer()
                        Text("\(glassesManager.connectedDeviceCount)")
                            .foregroundColor(.secondary)
                    }

                    if let device = glassesManager.connectedDevice {
                        HStack {
                            Text("Active Device")
                            Spacer()
                            Text(device)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("Streaming")
                        Spacer()
                        if glassesManager.isStreaming {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.red)
                                    .frame(width: 8, height: 8)
                                Text("Active")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Text("Inactive")
                                .foregroundColor(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if let profile = glassesManager.streamProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Stream")
                            Text(glassesManager.isPaused
                                 ? "Paused from the glasses. Tap the touchpad once to resume."
                                 : profile.summary)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Device Status")
                }

                if BuildFlavor.current.allowsExperimental {
                    Section {
                        NavigationLink {
                            GlassesLimitsView()
                        } label: {
                            Label("Glasses limits", systemImage: "slider.horizontal.3")
                        }
                    } footer: {
                        Text("Full-rate video, whole-sensor photos, sound from the glasses, the touchpad and buttons, nods and shakes, and speech on the glasses.")
                    }
                }

                // Camera Controls
                Section {
                    Button {
                        Task {
                            await glassesManager.startStreaming()
                        }
                    } label: {
                        Label("Start Camera Stream", systemImage: "video")
                    }
                    .disabled(glassesManager.isStreaming)

                    // Stages/updates the on-glasses developer component (DWA) via Meta AI.
                    // Sessions die with "Device unavailable"/"Session ended by device" when the
                    // DWA is missing ("DWA did not report its version" in the SDK log) — this is
                    // the SDK's recovery path for that state.
                    Button {
                        Task { await glassesManager.updateGlassesApp() }
                    } label: {
                        Label("Update the glasses app", systemImage: "arrow.down.circle")
                    }

                    Button {
                        Task { await glassesManager.updateGlassesFirmware() }
                    } label: {
                        Label("Update the glasses", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button {
                        Task {
                            await glassesManager.stopStreaming()
                        }
                    } label: {
                        Label("Stop Camera Stream", systemImage: "video.slash")
                    }
                    .disabled(!glassesManager.isStreaming)

                    Button {
                        Task {
                            await glassesManager.capturePhoto()
                        }
                    } label: {
                        Label("Capture Photo", systemImage: "camera")
                    }
                    .disabled(!glassesManager.isStreaming)
                } header: {
                    Text("Camera Controls")
                } footer: {
                    Text("Use camera controls to test glasses connectivity.")
                }
            }

            // Help Section
            Section {
                Link(destination: URL(string: "https://developer.meta.com/docs/wearables")!) {
                    HStack {
                        Text("Meta Wearables Documentation")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(.secondary)
                    }
                }

                NavigationLink {
                    GlassesCheckView()
                } label: {
                    Text("Glasses check")
                }

                NavigationLink {
                    TroubleshootingView()
                } label: {
                    Text("Troubleshooting")
                }
            } header: {
                Text("Help")
            }
        }
        .navigationTitle("Glasses")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Unregister Glasses",
            isPresented: $showingUnregisterConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unregister", role: .destructive) {
                Task {
                    await glassesManager.unregister()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects your glasses from Phoenix Fox. You will need to pair them again to use them.")
        }
        .confirmationDialog(
            "Disconnect & re-register?",
            isPresented: $showingReregisterConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect & re-register", role: .destructive) {
                Task { await glassesManager.disconnectAndReregister() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this when Developer Mode was turned on after you first registered. Meta AI will disconnect Phoenix Fox, then open again to register fresh so the app can appear under Developer mode apps. Do not do this on every launch.")
        }
        .alert("Error", isPresented: .constant(glassesManager.errorMessage != nil)) {
            Button("OK") {
                glassesManager.errorMessage = nil
            }
        } message: {
            if let error = glassesManager.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Methods

    /// Opens Meta AI. How it went is in `glassesManager.registration`, which this screen
    /// shows under the button.
    private func register() {
        Task { await glassesManager.register() }
    }
}

// MARK: - Troubleshooting View

struct TroubleshootingView: View {
    var body: some View {
        List {
            Section("Registration Issues") {
                TroubleshootingItem(
                    title: "Meta AI app not opening",
                    solution: "Make sure Meta AI app is installed and you're signed in."
                )
                TroubleshootingItem(
                    title: "Meta AI says “Internal error”",
                    solution: RegistrationStall.returnedUnconnected.steps.joined(separator: " ")
                )
                TroubleshootingItem(
                    title: "Registration fails",
                    solution: GlassesPreparation.steps.joined(separator: " ") + " " + GlassesPreparation.reason
                )
                TroubleshootingItem(
                    title: "App not appearing under Developer mode apps",
                    solution: "Turn Developer Mode on first, then Settings → Glasses → Disconnect & re-register once. A register done before Dev Mode will not list the app there (Meta #197). Real MetaAppID TestFlight builds can appear as Dev Mode apps while Dev Mode is on; MetaAppID 0 is only for pure local builds. For the release-channel path, turn Dev Mode off and accept the Wearables Developer Center Beta invite."
                )
            }

            Section("Connection Issues") {
                TroubleshootingItem(
                    title: "No devices found",
                    solution: "Ensure your glasses are paired with your iPhone via Bluetooth."
                )
                TroubleshootingItem(
                    title: "Streaming not starting",
                    solution: "Close other apps that might be using the glasses camera."
                )
                TroubleshootingItem(
                    title: "Poor video quality",
                    solution: "Make sure you have good lighting and stable Bluetooth connection."
                )
            }
        }
        .navigationTitle("Troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TroubleshootingItem: View {
    let title: String
    let solution: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(solution)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        GlassesSettingsView()
            .environmentObject(GlassesManager.shared)
    }
}
