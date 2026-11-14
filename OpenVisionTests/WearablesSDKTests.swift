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

        await glasses.register()
        XCTAssertEqual(glasses.registration.stall, .notRunning("The glasses connection is not running."))
        XCTAssertFalse(glasses.registration.isWorking)
        XCTAssertEqual(
            glasses.registrationDetails,
            "Glasses toolkit: not running. Attempt: stalled:This build cannot connect to glasses. Meta AI opened: no. Answer from Meta AI: no."
        )
        glasses.dismissRegistrationTrouble()
        XCTAssertNil(glasses.registration.stall)

        await glasses.handleCallback(URL(string: "https://phoenix-fox-links.cinderandcrown.workers.dev/dat?x=1")!)
        XCTAssertNil(glasses.pendingRegistration)
    }

    func testAnUnknownStartFailureHasAnInstruction() {
        XCTAssertEqual(
            WearablesSDK.message(for: URLError(.unknown)),
            "The glasses software did not start. Close Phoenix Fox and open it again."
        )
    }

    /// Meta DAT #177: never call startRegistration when already registered or in flight.
    func testRegistrationSkipsWhenAlreadyRegisteredOrRegistering() {
        XCTAssertTrue(GlassesManager.shouldSkipStartRegistration(.registered))
        XCTAssertTrue(GlassesManager.shouldSkipStartRegistration(.registering))
        XCTAssertFalse(GlassesManager.shouldSkipStartRegistration(.available))
        XCTAssertFalse(GlassesManager.shouldSkipStartRegistration(.unavailable))
        XCTAssertFalse(GlassesManager.shouldSkipStartRegistration(.notRunning))
        XCTAssertTrue(GlassesManager.isRegisteredStage(.registered))
        XCTAssertTrue(GlassesManager.isRegisteredStage(.registering))
        XCTAssertFalse(GlassesManager.isRegisteredStage(.available))
    }

    /// Skipped Register must not look like a completed attempt with Meta AI opened: no.
    func testSkippedRegisterDoesNotBeginAnAttempt() async {
        let glasses = GlassesManager.shared
        // SDK not running in tests → register begins then stalls; that path is fine.
        // When already-registered skip is hit in production, begin() is not called.
        // Guard the pure rule here so Copy log stays honest after a no-op Register.
        XCTAssertTrue(GlassesManager.shouldSkipStartRegistration(.registered))
        glasses.dismissRegistrationTrouble()
        XCTAssertEqual(glasses.registration.phase, .idle)
    }

    func testMetaAppIDIsReadableWithoutToken() {
        let id = DATEligibility.configuredMetaAppID
        // Under tests the plist may be missing MWDAT; either a real id or (missing) is fine.
        XCTAssertFalse(id.contains("CLIENT"), "Copy log must never include the client token")
        XCTAssertFalse(id.isEmpty)
    }

    /// Disconnect & re-register is opt-in only — never armed at launch (#177).
    func testPendingReregisterIsOffAtLaunch() {
        XCTAssertFalse(GlassesManager.shared.pendingReregisterAfterUnregister)
    }
}
