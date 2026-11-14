// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import AVFoundation
import SwiftUI

/// A short checklist for the glasses: registration, audio link, mic, a test tone, a test
/// look, and the relay. Accounts for DAT limits: HFP vs A2DP exclusivity, HFP settle
/// before camera, foreground-only raw frames, stream frames for store builds.
struct GlassesCheckView: View {
    @EnvironmentObject private var glassesManager: GlassesManager
    @EnvironmentObject private var settingsManager: SettingsManager

    @State private var toneNote: String?
    @State private var captureNote: String?
    @State private var busy = false

    private var audio: AudioSessionManager { .shared }
    private var network: NetworkPath { .shared }

    var body: some View {
        List {
            Section {
                row("Registration", glassesManager.isRegistered ? "Connected" : "Not connected")
                row("Devices in reach", "\(glassesManager.connectedDeviceCount)")
                row("Network", network.status.title)
            } header: {
                Text("Connection")
            } footer: {
                if !glassesManager.isRegistered {
                    Text("Pair the glasses in Meta AI, turn on Developer Mode, then Register.")
                }
            }

            Section {
                ForEach(audio.diagnosticLines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Picker("Speaker", selection: $settingsManager.settings.speakerPreference) {
                    ForEach(SpeakerPreference.allCases, id: \.self) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Toggle("Prefer glasses mic", isOn: $settingsManager.settings.preferGlassesMic)
            } header: {
                Text("Audio route")
            } footer: {
                Text("The glasses voice link (HFP) and the high-quality speaker link (A2DP) cannot run at the same time. HFP must settle before the camera starts. The glasses mic is mono 16 kHz.")
            }

            Section {
                Button {
                    playTone()
                } label: {
                    Label(busy ? "Playing…" : "Play test tone on current route", systemImage: "speaker.wave.2")
                }
                .disabled(busy)
                if let toneNote {
                    Text(toneNote).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Test tone")
            } footer: {
                Text(audio.destination.title)
            }

            Section {
                Button {
                    Task { await testCapture() }
                } label: {
                    Label(busy ? "Looking…" : "Test capture (stream frame)", systemImage: "camera")
                }
                .disabled(busy || !glassesManager.isRegistered)
                if let captureNote {
                    Text(captureNote).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Camera")
            } footer: {
                Text("Raw frames arrive only while Phoenix Fox is open on the screen. Full-sensor photos are owner-build only (DAT experimental; not for App Store). This test always uses a stream frame.")
            }

            Section {
                row("Relay configured", settingsManager.settings.isOwnAssistantConfigured ? "Yes" : "No")
                row("Grok key", settingsManager.settings.isGrokConfigured ? "On this phone" : "Not set")
                row("Full-sensor photo", BuildFlavor.current.allowsExperimental && settingsManager.settings.glasses.highResolutionStills ? "Allowed in this build" : "Off (stream frames)")
            } header: {
                Text("Brain")
            }
        }
        .navigationTitle("Glasses check")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func playTone() {
        busy = true
        toneNote = nil
        AudioSessionManager.shared.logSpeaking()
        SoundService.shared.playWakeWordSound()
        toneNote = "Tone played on: \(audio.destination.title). Link: \(audio.linkMode.title)."
        busy = false
    }

    private func testCapture() async {
        busy = true
        captureNote = nil
        defer { busy = false }
        if UIApplication.shared.applicationState != .active {
            captureNote = "Unlock the phone and keep Phoenix Fox open. Raw frames do not arrive in the background."
            return
        }
        await AudioSessionManager.shared.waitUntilCameraSafe()
        await glassesManager.startStreaming()
        // One short wait for a frame without using the beta photo API.
        try? await Task.sleep(for: .milliseconds(400))
        let frame = glassesManager.lastFrame
        await glassesManager.stopStreaming()
        if let frame, let data = ImageBudget.jpeg(frame.jpegData(compressionQuality: 0.8)) {
            captureNote = "Got a stream frame (\(data.count / 1024) KB after budget). HFP settled: \(audio.hfpSettled ? "yes" : "no")."
        } else {
            captureNote = glassesManager.errorMessage ?? "No frame arrived. Check registration, Developer Mode, and that the glasses are worn."
        }
    }
}

#Preview {
    NavigationStack {
        GlassesCheckView()
            .environmentObject(GlassesManager.shared)
            .environmentObject(SettingsManager.shared)
    }
}
