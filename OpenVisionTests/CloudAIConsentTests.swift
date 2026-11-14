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
    func testPrunesExpiredFaces() {
        let old = FaceRecord(name: "Ada", consentAt: Date(timeIntervalSinceNow: -40 * 24 * 3600), prints: [Data([1])])
        let fresh = FaceRecord(name: "Grace", consentAt: Date(), prints: [Data([2])])
        let kept = FaceLedger.pruningExpired([old, fresh], asOf: Date(), retentionDays: 30)
        XCTAssertEqual(kept.map(\.name), ["Grace"])
    }
}

final class AccessibilityPrivacyDefaultsTests: XCTestCase {
    func testGuideCloudDefaultIsOff() {
        XCTAssertFalse(AccessibilitySettings().guideCloudDescriptions)
    }

    func testQwen3BNotOfferedInStandardBuild() {
        // BuildFlavor.current in unit tests follows the test host Info.plist; assert the filter API.
        XCTAssertEqual(GemmaLocalModel.qwen3B.isOffered, BuildFlavor.current == .owner)
    }
}
