// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class ReviewerDemoTests: XCTestCase {
    func testTimeIsAlwaysAnsweredWithoutDemoMode() {
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12, minute: 0))!
        let line = ReviewerDemo.reply(to: "what time is it", demoEnabled: false, now: noon)
        XCTAssertEqual(line?.hasPrefix("It's "), true)
        XCTAssertGreaterThan(line?.count ?? 0, 5)
    }

    func testHelpRequiresDemoMode() {
        XCTAssertNil(ReviewerDemo.reply(to: "what can you do", demoEnabled: false))
        let line = ReviewerDemo.reply(to: "what can you do", demoEnabled: true)
        XCTAssertEqual(line?.contains("App Review demo"), true)
    }

    func testPrivacyLineOnlyInDemo() {
        XCTAssertNil(ReviewerDemo.reply(to: "where is the privacy policy", demoEnabled: false))
        XCTAssertEqual(
            ReviewerDemo.reply(to: "privacy policy", demoEnabled: true)?.contains("Privacy and Data"),
            true
        )
    }
}
