// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

@MainActor
final class WearablesSDKTests: XCTestCase {

    /// The glasses SDK stops the app if it is read before it is configured. Tests run inside
    /// the app without configuring it, so reaching this line at all shows the app survives.
    func testTheAppRunsWhenTheGlassesSDKHasNotStarted() {
        XCTAssertTrue(AppLaunch.isHostingTests)
        XCTAssertNil(WearablesSDK.interface)
        XCTAssertEqual(GlassesUnavailable().reason, "The glasses connection is not running.")
    }

    func testGlassesActionsReportTheSDKInsteadOfCrashing() async {
        let glasses = GlassesManager.shared
        await glasses.startStreaming()
        XCTAssertEqual(glasses.errorMessage, "The glasses connection is not running.")
        XCTAssertFalse(glasses.isStreaming)

        do {
            try await glasses.register()
            XCTFail("expected the SDK to be unavailable")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The glasses connection is not running.")
        }

        await glasses.handleCallback(URL(string: "https://phoenix-fox-links.cinderandcrown.workers.dev/dat?x=1")!)
        XCTAssertNil(glasses.pendingRegistration)
    }

    func testAnUnknownStartFailureHasAnInstruction() {
        XCTAssertEqual(
            WearablesSDK.message(for: URLError(.unknown)),
            "The glasses software did not start. Close Phoenix Fox and open it again."
        )
    }
}
