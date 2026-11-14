// SPDX-License-Identifier: Apache-2.0 AND MIT
// Derived from OpenVision (https://github.com/rayl15/OpenVision), MIT License,
// Copyright (c) 2026 OpenVision Contributors. Changes by Cinder and Crown LLC are
// licensed under Apache-2.0. See LICENSE, NOTICE, and THIRD_PARTY_NOTICES.md.
// OpenVision - AdditionalInstructionsView.swift
// Custom AI instructions editor

import SwiftUI

struct AdditionalInstructionsView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var instructions: String = ""

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Editor
            TextEditor(text: $instructions)
                .padding()
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))

            // Character count
            HStack {
                Spacer()
                Text("\(instructions.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("Custom Instructions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveInstructions()
                    dismiss()
                }
            }

            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            instructions = settingsManager.settings.userPrompt
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Divider()

                Text("These instructions will be added to the AI assistant's system prompt. Use this to customize behavior, provide context about yourself, or set preferences.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Methods

    private func saveInstructions() {
        settingsManager.settings.userPrompt = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        settingsManager.saveNow()
    }
}

#Preview {
    NavigationStack {
        AdditionalInstructionsView()
            .environmentObject(SettingsManager.shared)
    }
}
