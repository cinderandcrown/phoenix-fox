// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import SwiftUI

struct MusicSettingsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Picker("Service", selection: $settingsManager.settings.musicProvider) {
                    ForEach(MusicProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            } header: {
                Text("Provider")
            } footer: {
                Text("Spotify uses the official App Remote path when the SpotifyiOS SDK is linked, plus Web API over PKCE (no client secret in the app). Apple Music uses MusicKit. Music plays on the glasses over A2DP; a voice command briefly uses HFP, then stereo is restored.")
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    if busy {
                        ProgressView()
                    } else {
                        Text(connectTitle)
                    }
                }
                .disabled(busy)

                if settingsManager.settings.musicProvider == .spotify, SpotifyPKCEAuth.shared.isSignedIn {
                    Button("Sign out of Spotify", role: .destructive) {
                        SpotifyPKCEAuth.shared.signOut()
                        status = "Signed out."
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                if let status {
                    Text(status)
                } else if settingsManager.settings.musicProvider == .spotify {
                    Text("Add SpotifyClientID in Config.xcconfig / Info.plist. Development Mode allows 5 Spotify users; Extended Quota is required for public release (docs/SDK_NOTES.md).")
                } else {
                    Text("Apple Music asks for permission the first time you connect.")
                }
            }

            Section {
                Text("Say “play my Discover Weekly”, “skip”, “what song is this”, “turn it down”, or “save this song”.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Voice")
            }
        }
        .navigationTitle("Music")
    }

    private var connectTitle: String {
        switch settingsManager.settings.musicProvider {
        case .spotify:
            return SpotifyPKCEAuth.shared.isSignedIn ? "Reconnect Spotify" : "Connect Spotify"
        case .appleMusic:
            return AppleMusicProvider.shared.isConfigured ? "Reconnect Apple Music" : "Connect Apple Music"
        }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        do {
            try await MusicCoordinator.shared.activeProvider.connect()
            status = "Connected."
        } catch {
            status = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        MusicSettingsView()
            .environmentObject(SettingsManager.shared)
    }
}
