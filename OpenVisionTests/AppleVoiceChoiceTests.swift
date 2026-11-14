// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class AppleVoiceChoiceTests: XCTestCase {
    private let compact = AppleVoiceCandidate(
        identifier: "com.apple.voice.compact.en-US.Samantha",
        name: "Samantha",
        qualityRank: 1,
        isPersonal: false,
        language: "en-US"
    )
    private let enhanced = AppleVoiceCandidate(
        identifier: "com.apple.ttsbundle.siri_female_en-US_compact",
        name: "Samantha (Enhanced)",
        qualityRank: 2,
        isPersonal: false,
        language: "en-US"
    )
    private let premium = AppleVoiceCandidate(
        identifier: "com.apple.voice.premium.en-US.Zoe",
        name: "Zoe",
        qualityRank: 3,
        isPersonal: false,
        language: "en-US"
    )
    private let personal = AppleVoiceCandidate(
        identifier: "com.apple.speech.personalvoice.abc",
        name: "My Voice",
        qualityRank: 3,
        isPersonal: true,
        language: "en-US"
    )

    func testPrefersPremiumOverEnhancedAndCompact() {
        let pick = AppleVoiceChoice.pick(
            from: [compact, enhanced, premium],
            preferredIdentifier: nil
        )
        XCTAssertEqual(pick?.identifier, premium.identifier)
    }

    func testPrefersEnhancedWhenNoPremium() {
        let pick = AppleVoiceChoice.pick(from: [compact, enhanced], preferredIdentifier: nil)
        XCTAssertEqual(pick?.identifier, enhanced.identifier)
    }

    func testNeverAutoPicksCompactWhenBetterExists() {
        let pick = AppleVoiceChoice.pick(from: [compact, enhanced], preferredIdentifier: nil)
        XCTAssertNotEqual(pick?.qualityRank, 1)
    }

    func testHonorsExplicitUserPickEvenIfCompact() {
        let pick = AppleVoiceChoice.pick(
            from: [compact, premium],
            preferredIdentifier: compact.identifier
        )
        XCTAssertEqual(pick?.identifier, compact.identifier)
    }

    func testPersonalVoiceWinsWhenAuthorizedAndPresent() {
        let pick = AppleVoiceChoice.pick(
            from: [compact, premium, personal],
            preferredIdentifier: nil
        )
        XCTAssertEqual(pick?.identifier, personal.identifier)
    }

    func testNeedsBetterVoicesHintWhenOnlyCompact() {
        XCTAssertTrue(AppleVoiceChoice.needsBetterVoicesHint(voices: [compact]))
        XCTAssertFalse(AppleVoiceChoice.needsBetterVoicesHint(voices: [compact, premium]))
    }
}
