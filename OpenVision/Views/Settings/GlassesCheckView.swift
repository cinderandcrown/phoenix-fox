// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import AVFoundation
import SwiftUI
import UIKit

/// A short checklist for the glasses: registration, audio link, mic, a test tone, a test
/// look, and the relay. Accounts for DAT limits: HFP vs A2DP exclusivity, HFP settle
/// before camera, foreground-only raw frames, stream frames for store builds.
struct GlassesCheckView: View {
    @EnvironmentObject private var glassesManager: GlassesManager
    @EnvironmentObject private var settingsManager: SettingsManager
    @ObservedObject private var link = GlassesLink.shared

    @State private var toneNote: String?
    @State private var captureNote: String?
    @State private var busy = false
    @State private var copied = false

    private var audio: AudioSessionManager { .shared }
    private var network: NetworkPath { .shared }

    var body: some View {
        List {
            Section {
                row("Registration", glassesManager.isRegistered ? "Registered" : "Not registered")
                row("SDK stage", glassesManager.registrationStage.rawValue)
                row("Attempt", attemptPhaseLabel)
                row("Devices listed", "\(glassesManager.connectedDeviceCount)")
                row("DAT link", glassesManager.deviceLinkStateLabel)
                row("Link ready", glassesManager.deviceLinkConnected ? "yes" : "no")
                row("Network", network.status.title)
                if let sdkError = glassesManager.lastSDKError {
                    Text(sdkError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if let stall = glassesManager.registration.stall {
                    Text(stall.title)
                        .foregroundStyle(.red)
                    Text(stall.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Connection")
            } footer: {
                if !glassesManager.isRegistered {
                    Text("Pair the glasses in Meta AI, turn on Developer Mode, then Register. Details: \(glassesManager.registrationDetails)")
                } else if !glassesManager.deviceLinkConnected {
                    Text("Registered is not enough for the camera. DAT needs LinkState.connected. Wear the glasses, unfold the arms, and keep Meta AI connected.")
                }
            }

            Section {
                if link.logs.isEmpty {
                    Text("No registration events yet. Tap Register on the Glasses screen, then come back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(link.logs.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Button {
                    copyLog()
                } label: {
                    Label(copied ? "Copied" : "Copy log", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(link.logs.isEmpty)
            } header: {
                Text("Registration log")
            } footer: {
                Text("Each line is a registration state or error without tokens or IDs. Copy and paste into a bug report if connect fails.")
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

    private var attemptPhaseLabel: String {
        switch glassesManager.registration.phase {
        case .idle: return "idle"
        case .opening: return "opening Meta AI"
        case .away: return "in Meta AI"
        case .confirming: return "confirming"
        case .awaitingConsent: return "awaiting Connect"
        case .stalled(let stall): return "stalled: \(stall.title)"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func copyLog() {
        let header = [
            "Phoenix Fox glasses log",
            glassesManager.registrationDetails,
            "Registered: \(glassesManager.isRegistered)",
            "Devices listed: \(glassesManager.connectedDeviceCount)",
            "DAT link: \(glassesManager.deviceLinkStateLabel)",
            "Link ready: \(glassesManager.deviceLinkConnected)",
            "Last SDK error: \(glassesManager.lastSDKError ?? "(none)")",
            "Audio: \(audio.destination.title)",
            "Link mode: \(audio.linkMode.title)",
            "---",
        ].joined(separator: "\n")
        UIPasteboard.general.string = header + "\n" + link.logs.joined(separator: "\n")
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
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
