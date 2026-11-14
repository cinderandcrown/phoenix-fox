// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// One control that wipes history, memories, face ledger, keys, and caches on this phone.
// There is no Phoenix Fox cloud account to delete.

import Foundation

@MainActor
enum DataDeletion {
    /// Erases local user data. Secrets in the Keychain are cleared via SettingsManager.
    static func eraseAllOnThisPhone() {
        CloudAIConsent.withdraw()
        FaceRecognitionConsent.withdrawWearerNotice()
        ConversationManager.shared.deleteAllConversations()
        AccessFaces.shared.forgetAll()
        AccessStore.remove("faces")
        AccessStore.remove("routines")
        AccessStore.remove("reminders")
        AccessStore.remove("trail")
        AccessStore.remove("task")
        AccessStore.remove("transcripts")
        WorkshopCoordinator.shared.eraseEverything()
        OAuthTokenStore.shared.signOutAllProviders()
        clearModelCaches()
        SettingsManager.shared.resetToDefaults()
    }

    private static func clearModelCaches() {
        let fm = FileManager.default
        let urls = [
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        for root in urls {
            for name in ["huggingface", "models", "mlx", "whisperkit", "kokoro", "LocalModels"] {
                let path = root.appendingPathComponent(name, isDirectory: true)
                try? fm.removeItem(at: path)
            }
        }
    }
}
