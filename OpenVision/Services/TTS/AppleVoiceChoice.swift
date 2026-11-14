// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Pure ranking of Apple system voices so unit tests can run on Linux without AVFoundation.
// Real AVSpeechSynthesisVoice values are mapped in TTSService.

import Foundation

/// Ranked Apple TTS candidate. Higher `qualityRank` is more natural.
struct AppleVoiceCandidate: Equatable, Sendable {
    let identifier: String
    let name: String
    /// 3 = premium, 2 = enhanced, 1 = default/compact, 0 = unknown.
    let qualityRank: Int
    let isPersonal: Bool
    let language: String

    var isCompactOrDefault: Bool { qualityRank <= 1 }
}

enum AppleVoiceChoice {
    /// Pick the voice to speak with.
    ///
    /// Order: explicit user pick (if still installed) → authorized Personal Voice →
    /// highest-quality English voice (premium, then enhanced). Compact/default is only
    /// used when nothing better is installed.
    static func pick(
        from voices: [AppleVoiceCandidate],
        preferredIdentifier: String?,
        languagePrefix: String = "en"
    ) -> AppleVoiceCandidate? {
        let pool = voices.filter { $0.language.lowercased().hasPrefix(languagePrefix.lowercased()) }
        let search = pool.isEmpty ? voices : pool

        if let preferredIdentifier,
           let preferred = search.first(where: { $0.identifier == preferredIdentifier }) {
            return preferred
        }

        if let personal = search.first(where: \.isPersonal) {
            return personal
        }

        return search.max { a, b in
            if a.qualityRank != b.qualityRank { return a.qualityRank < b.qualityRank }
            return a.name > b.name
        }
    }

    /// True when the wearer only has compact/default English voices — Settings should
    /// point them at iOS Spoken Content downloads.
    static func needsBetterVoicesHint(voices: [AppleVoiceCandidate], languagePrefix: String = "en") -> Bool {
        let pool = voices.filter { $0.language.lowercased().hasPrefix(languagePrefix.lowercased()) }
        guard !pool.isEmpty else { return true }
        return pool.allSatisfy(\.isCompactOrDefault)
    }

    static func qualityRank(rawValue: Int) -> Int {
        // AVSpeechSynthesisVoiceQuality: default=1, enhanced=2, premium=3 (Apple's raw values).
        switch rawValue {
        case 3: return 3
        case 2: return 2
        case 1: return 1
        default: return 0
        }
    }
}
