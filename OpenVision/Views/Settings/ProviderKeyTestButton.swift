// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Shared "Test key" control. Runs a tiny authenticated request; never logs the key.

import SwiftUI

struct ProviderKeyTestButton: View {
    let provider: AIProviderID
    let apiKey: String
    @Binding var status: String?

    @State private var busy = false

    var body: some View {
        Button {
            Task { await test() }
        } label: {
            HStack {
                Label(busy ? "Testing…" : "Test key", systemImage: busy ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                Spacer()
                if busy { ProgressView() }
            }
        }
        .disabled(busy || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func test() async {
        busy = true
        status = nil
        defer { busy = false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never print or log `key`.
        do {
            try await AIProviderRegistry.provider(for: provider).testKey(key)
            status = "Key works with \(provider.displayName)."
        } catch {
            status = error.localizedDescription
        }
    }
}
