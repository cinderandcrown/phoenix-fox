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
    @State private var parityNote: String?
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
                row("MetaAppID", DATEligibility.configuredMetaAppID)
                row("DAT path", DATEligibility.usesDeveloperModeAppID ? "Dev Mode (AppID 0)" : "Release channel")
                row("isDevMode", DATEligibility.isDevModeLabel(from: WearablesSDK.interface))
                row("Bluetooth", WearablesSDK.bluetoothAtConfigure)
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
                    Text("Registered lists a device; DAT link still down. If Phoenix Fox is missing under Meta AI → Developer mode apps, use Glasses → Disconnect & re-register once (Dev Mode after prior register). Else Path B: release-channel invite with Dev Mode off. MetaAppID 0 is optional local-only. Probe below; if session.start fails while disconnected, toggle phone Bluetooth (DAT #150).")
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
                if glassesManager.isRegistered {
                    Button {
                        Task { await glassesManager.disconnectAndReregister() }
                    } label: {
                        Label(
                            glassesManager.pendingReregisterAfterUnregister
                                ? "Disconnecting…"
                                : "Disconnect & re-register",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .disabled(busy || glassesManager.pendingReregisterAfterUnregister || glassesManager.registration.isWorking)
                }
                Button {
                    Task { await runParityProbe() }
                } label: {
                    Label(busy ? "Running probe…" : "Run CameraAccess probe", systemImage: "stethoscope")
                }
                .disabled(busy || !glassesManager.isRegistered)
                if let parityNote {
                    Text(parityNote)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text("DAT sample parity")
            } footer: {
                Text("Disconnect & re-register is for Dev Mode turned on after a prior register (Meta #177/#197) — once, not every launch. The probe runs Meta’s CameraAccess sequence only.")
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
        var header = [
            "Phoenix Fox glasses log",
            glassesManager.registrationDetails,
            "Registered: \(glassesManager.isRegistered)",
            "Devices listed: \(glassesManager.connectedDeviceCount)",
            "Audio: \(audio.destination.title)",
            "Link mode: \(audio.linkMode.title)",
        ]
        header.append(contentsOf: DATEligibility.snapshotLines(
            wearables: WearablesSDK.interface,
            bluetooth: WearablesSDK.bluetoothAtConfigure,
            linkLabel: glassesManager.deviceLinkStateLabel,
            linkConnected: glassesManager.deviceLinkConnected,
            lastSDKError: glassesManager.lastSDKError
        ))
        header.append("---")
        UIPasteboard.general.string = header.joined(separator: "\n") + "\n" + link.logs.joined(separator: "\n")
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func runParityProbe() async {
        busy = true
        parityNote = nil
        defer { busy = false }
        parityNote = await CameraAccessParity.runProbe(startStream: true)
    }

    private func playTone() {
        busy = true
        toneNote = nil
        try? AudioSessionManager.shared.ensurePhoneMicReady()
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
