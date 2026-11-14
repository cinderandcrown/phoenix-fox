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

    func testCloudBackendsNeedConsent() {
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .grok, defaults: defaults))
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .openAI, defaults: defaults))
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .ownAssistant, defaults: defaults))
        CloudAIConsent.accept(defaults: defaults)
        XCTAssertTrue(CloudAIConsent.allowsCloudSend(backend: .grok, defaults: defaults))
        XCTAssertTrue(CloudAIConsent.isAccepted(defaults: defaults))
    }

    func testWithdrawClearsConsent() {
        CloudAIConsent.accept(defaults: defaults)
        CloudAIConsent.withdraw(defaults: defaults)
        XCTAssertFalse(CloudAIConsent.isAccepted(defaults: defaults))
        XCTAssertFalse(CloudAIConsent.allowsCloudSend(backend: .claude, defaults: defaults))
    }
}
