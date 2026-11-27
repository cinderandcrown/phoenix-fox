// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The captions screen: what is being said now, in large type, with the transcripts the
// wearer chose to keep and the sounds that raised an alert.

import SwiftUI

struct LiveCaptionsView: View {
    @ObservedObject private var captions = LiveCaptions.shared
    @ObservedObject private var sounds = SoundAlertService.shared
    @State private var status = ""

    var body: some View {
        List {
            Section {
                Toggle("Live captions", isOn: Binding(
                    get: { captions.isOn },
                    set: { on in report(on ? LiveCaptions.shared.start() : LiveCaptions.shared.stop()) }
                ))
                if !status.isEmpty {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Now") {
                if captions.book.lines.isEmpty && captions.book.live.isEmpty {
                    Text(captions.isOn ? "Listening. Words appear here as people speak." : "Captions are off.")
                        .foregroundStyle(.secondary)
                }
                ForEach(captions.book.lines.suffix(40)) { line in
                    Text(line.text)
                        .font(.title3)
                        .accessibilityLabel("\(line.at.formatted(date: .omitted, time: .shortened)): \(line.text)")
                }
                if !captions.book.live.isEmpty {
                    Text(captions.book.live)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if !captions.book.lines.isEmpty {
                    Button("Save this conversation") { report(LiveCaptions.shared.save()) }
                    Button("Clear captions", role: .destructive) { report(LiveCaptions.shared.clear()) }
                }
            }

            if !sounds.recent.isEmpty {
                Section("Sounds heard") {
                    ForEach(Array(sounds.recent.enumerated()), id: \.offset) { _, alert in
                        LabeledContent(alert.kind.message, value: alert.at.formatted(date: .omitted, time: .shortened))
                    }
                }
            }

            Section {
                if captions.saved.isEmpty {
                    Text("Nothing saved. Say \"Hey Phoenix, save this conversation\" while captions are on.")
                        .foregroundStyle(.secondary)
                }
                ForEach(captions.saved) { transcript in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(transcript.savedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.headline)
                        Text(transcript.text)
                            .font(.callout)
                            .lineLimit(6)
                        HStack(spacing: 24) {
                            ShareLink("Share", item: transcript.text)
                            Button("Delete", role: .destructive) { captions.delete(transcript) }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Saved transcripts")
            } footer: {
                Text("Saved transcripts are sealed on this phone and are not in backups. A transcript holds other people's words, so ask them before you share one. Captions come from speech recognition and contain mistakes. Do not rely on them for medical, legal, or safety decisions.")
            }
        }
        .navigationTitle("Captions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func report(_ line: String) {
        status = line
        AccessibilityNotification.Announcement(line).post()
    }
}

/// The alert shown over the app when a sound or the wearer's name is heard.
struct AccessBannerView: View {
    @ObservedObject private var banner = AccessBanner.shared

    var body: some View {
        if let message = banner.message {
            Button {
                banner.dismiss()
            } label: {
                Label(message, systemImage: banner.urgent ? "exclamationmark.triangle.fill" : "ear.fill")
                    .font(.title2.bold())
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .foregroundStyle(banner.urgent ? Color.black : Color.white)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(banner.urgent ? Color.yellow : Color.blue)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .accessibilityLabel("Sound alert: \(message)")
            .accessibilityHint("Dismisses the alert.")
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
