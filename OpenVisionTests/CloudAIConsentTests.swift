// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class CloudAIConsentTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CloudAIConsentTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.suiteName!)
        defaults = nil
        super.tearDown()
    }

    func testOnDeviceBackendsDoNotNeedConsent() {
        XCTAssertTrue(CloudAIConsent.allowsCloudSend(backend: .appleFoundation, defaults: defaults))
        XCTAssertTrue(CloudAIConsent.allowsCloudSend(backend: .localGemma, defaults: defaults))
    }

    func testCloudBackendsNeedPerProviderConsent() {
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .grok, defaults: defaults))
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .openAI, defaults: defaults))
        CloudAIConsent.accept(.grok, defaults: defaults)
        XCTAssertTrue(CloudAIConsent.allowsCloudSend(backend: .grok, defaults: defaults))
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .openAI, defaults: defaults))
    }

    func testWithdrawClearsConsent() {
        CloudAIConsent.accept(.claude, defaults: defaults)
        CloudAIConsent.withdraw(.claude, defaults: defaults)
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .claude, defaults: defaults))
    }

    func testLegacyKeyMigratesToAllProviders() {
        defaults.set(Date().timeIntervalSince1970, forKey: CloudAIConsent.legacyDefaultsKey)
        XCTAssertTrue(CloudAIConsent.allowsCloudSend(backend: .ownAssistant, defaults: defaults))
        XCTAssertNil(defaults.object(forKey: CloudAIConsent.legacyDefaultsKey))
    }
}

final class FaceLedgerExpiryTests: XCTestCase {
    func testPrunesAfterDaysWithoutMatch() {
        let stale = FaceRecord(
            name: "Ada",
            consentAt: Date(timeIntervalSinceNow: -60 * 24 * 3600),
            prints: [Data([1])],
            lastSeen: Date(timeIntervalSinceNow: -40 * 24 * 3600)
        )
        let recentMatch = FaceRecord(
            name: "Grace",
            consentAt: Date(timeIntervalSinceNow: -60 * 24 * 3600),
            prints: [Data([2])],
            lastSeen: Date(timeIntervalSinceNow: -2 * 24 * 3600)
        )
        let neverMatchedFresh = FaceRecord(
            name: "Marie",
            consentAt: Date(timeIntervalSinceNow: -2 * 24 * 3600),
            prints: [Data([3])]
        )
        let kept = FaceLedger.pruningExpired(
            [stale, recentMatch, neverMatchedFresh],
            asOf: Date(),
            retentionDays: 30
        )
        XCTAssertEqual(Set(kept.map(\.name)), Set(["Grace", "Marie"]))
    }

    func testRetentionClamp() {
        XCTAssertEqual(FaceRecognitionConsent.clampedRetentionDays(0), 1)
        XCTAssertEqual(FaceRecognitionConsent.clampedRetentionDays(1), 1)
        XCTAssertEqual(FaceRecognitionConsent.clampedRetentionDays(30), 30)
        XCTAssertEqual(FaceRecognitionConsent.clampedRetentionDays(90), 30)
    }

    func testOneDayRetention() {
        let dayOld = FaceRecord(
            name: "Ada",
            consentAt: Date(timeIntervalSinceNow: -2 * 24 * 3600),
            prints: [Data([1])]
        )
        let kept = FaceLedger.pruningExpired([dayOld], asOf: Date(), retentionDays: 1)
        XCTAssertTrue(kept.isEmpty)
    }

    func testForgetByName() {
        let records = [
            FaceRecord(name: "Ada", consentAt: Date(), prints: [Data([1])]),
            FaceRecord(name: "Grace", consentAt: Date(), prints: [Data([2])]),
        ]
        let next = FaceLedger.forgetting(name: "ada", in: records)
        XCTAssertEqual(next.map(\.name), ["Grace"])
    }

    func testForgetEveryoneEmpties() {
        let records = [FaceRecord(name: "Ada", consentAt: Date(), prints: [Data([1])])]
        XCTAssertTrue(FaceLedger.forgetting(name: "Ada", in: records).isEmpty)
    }

    func testSavingRequiresExplicitConsentTimestamp() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let saved = FaceLedger.saving(
            print: Data([9]),
            for: "Ada",
            consentAt: when,
            consentSource: "spoken_yes",
            in: []
        )
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].consentAt, when)
        XCTAssertEqual(saved[0].consentSource, "spoken_yes")
        XCTAssertNil(saved[0].lastSeen)
    }
}

final class PrivacyFeatureFlagTests: XCTestCase {
    func testMetaTelemetryAlwaysOff() {
        XCTAssertFalse(PrivacyFeatureFlags.metaDATTelemetry)
        XCTAssertFalse(PrivacyFeatureFlag.metaDATTelemetry.isEnabled())
        PrivacyFeatureFlag.metaDATTelemetry.setEnabled(true)
        XCTAssertFalse(PrivacyFeatureFlag.metaDATTelemetry.isEnabled())
    }

    func testPublisherConstants() {
        XCTAssertEqual(PublisherIdentity.legalName, "Cinder and Crown LLC")
        XCTAssertEqual(PublisherIdentity.privacyEmail, "privacy@cinderandcrown.com")
    }
}

final class AccessibilityPrivacyDefaultsTests: XCTestCase {
    func testGuideCloudDefaultIsOff() {
        XCTAssertFalse(AccessibilitySettings().guideCloudDescriptions)
    }

    func testFaceRecognitionDefaultOff() {
        XCTAssertFalse(AccessibilitySettings().faceRecognition)
        XCTAssertEqual(AccessibilitySettings().faceRetentionDays, 30)
    }

    func testQwen3BNotOfferedInStandardBuild() {
        XCTAssertEqual(GemmaLocalModel.qwen3B.isOffered, BuildFlavor.current == .owner)
    }
}
