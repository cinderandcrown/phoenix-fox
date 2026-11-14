// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Maps docs/CAPABILITIES.md "Minimum acceptance scenarios" to automated checks.
// Simulator / pure-Swift results are never reported as glasses hardware results.
// Scenarios that need real glasses or Mock Device Kit on a Mac are XCTSkip'd with
// an explicit UNVERIFIED reason (see docs/SDK_NOTES.md acceptance matrix).

import XCTest
@testable import PhoenixFox

final class CapabilitiesAcceptanceTests: XCTestCase {

    /// 1. Clean install, no glasses paired → useful onboarding and preview.
    func testScenario1_CleanInstallOnboardingHasNextAction() {
        let phase = WearableSessionPhase.idle
        XCTAssertEqual(phase.nextAction.title, "Connect glasses")
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: nil), "Open Meta AI")
    }

    /// 2. Connect / register compatible glasses → visible status and permission intent.
    func testScenario2_RegistrationPhasesSurfaceStatus() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        XCTAssertTrue(attempt.isWorking)
        XCTAssertNil(attempt.stall)
        _ = attempt.handedOff()
        XCTAssertTrue(attempt.isWorking)
    }

    /// 3. Deny permission → no streaming; clear retry/settings path.
    func testScenario3_PermissionRequiredHasRetryPath() {
        let action = WearableSessionPhase.permissionRequired.nextAction
        XCTAssertTrue(action.title.lowercased().contains("allow") || action.title.lowercased().contains("camera"))
        XCTAssertFalse(action.detail.isEmpty)
        var machine = WearableSessionMachine(phase: .permissionRequired)
        XCTAssertNoThrow(try machine.transition(to: .failed).get())
        XCTAssertEqual(machine.phase.nextAction.title, "Retry")
    }

    /// 4. Start camera session → bounded preview, meaningful status, user-controlled stop.
    func testScenario4_SessionStartStopPath() {
        var machine = WearableSessionMachine(phase: .ready)
        XCTAssertNoThrow(try machine.transition(to: .starting).get())
        XCTAssertNoThrow(try machine.transition(to: .active).get())
        XCTAssertEqual(machine.phase.nextAction.title, "Stop when done")
        XCTAssertNoThrow(try machine.transition(to: .stopping).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())
    }

    /// 5. Trigger AI action → correct reply grounded in current frame, timeouts, cancellation.
    /// Pure path: glasses SDK absent in unit-test host → error, no crash, no stream.
    @MainActor
    func testScenario5_AIActionWithoutSDKDoesNotStream() async {
        let glasses = GlassesManager.shared
        await glasses.startStreaming()
        XCTAssertFalse(glasses.isStreaming)
        XCTAssertNotNil(glasses.errorMessage)
    }

    /// 6. Disconnect mid-inference → end session, discard stale output, repair UI state.
    func testScenario6_DisconnectTransitionsToRecoveringOrFailed() {
        var machine = WearableSessionMachine(phase: .active)
        XCTAssertNoThrow(try machine.transition(to: .recovering).get())
        XCTAssertEqual(machine.phase.nextAction.title, "Wait")
        XCTAssertNoThrow(try machine.transition(to: .ready).get())
    }

    /// 7. Background or interruption → documented teardown and safe restart.
    func testScenario7_InterruptionThenRecover() {
        var machine = WearableSessionMachine(phase: .active)
        XCTAssertNoThrow(try machine.transition(to: .interrupted).get())
        XCTAssertEqual(machine.phase.nextAction.title, "Resume")
        XCTAssertNoThrow(try machine.transition(to: .recovering).get())
        XCTAssertNoThrow(try machine.transition(to: .ready).get())
    }

    /// 8. Displayless glasses → spoken or phone fallback; no invisible display controls.
    func testScenario8_DisplaylessFallbackIsDocumented() {
        // Adventurer / metaGlasses is displayless; HUD must no-op without display.
        XCTAssertEqual(GlassesProductTarget.v1DeviceType, .metaGlasses)
        XCTAssertTrue(GlassesProductTarget.isV1Target(.metaGlasses))
        // Next action when ready never requires a lens UI.
        let detail = WearableSessionPhase.ready.nextAction.detail.lowercased()
        XCTAssertFalse(detail.contains("lens"))
        XCTAssertFalse(detail.contains("hud"))
    }

    /// 9. Display glasses → supported high-contrast UI; real-device proof.
    func testScenario9_DisplayGlasses_UNVERIFIED_NeedsHardwareOrDisplaySample() throws {
        throw XCTSkip(
            "UNVERIFIED: Meta Ray-Ban Display HUD cards need display hardware or the official DisplayAccess sample path. Mock Device Kit display simulation is limited. See docs/SDK_NOTES.md."
        )
    }

    /// 10. Release gate → documented SDK version, distribution eligibility, privacy disclosure.
    func testScenario10_ReleaseGateDocumentsPinnedSDK() {
        // Pinned version and distribution caveats live in docs; this asserts the app's
        // compile-time glasses requirements stay aligned with CAPABILITIES / GLASSES_SDK.
        XCTAssertEqual(GlassesRequirements.metaAIVersion, 292)
        XCTAssertEqual(GlassesRequirements.glassesVersion, 128)
        // Standard (App Store–shaped) builds strip Meta-labeled experimental capabilities.
        var experimental = GlassesCapabilitySettings()
        experimental.controls = true
        experimental.captureButton = true
        experimental.headGestures = true
        experimental.highResolutionStills = true
        experimental.ambientAudio = true
        experimental.onGlassesSpeech = true
        let store = experimental.allowed(in: .standard)
        XCTAssertFalse(store.controls)
        XCTAssertFalse(store.onGlassesSpeech)
        XCTAssertFalse(store.highResolutionStills)
        XCTAssertFalse(store.ambientAudio)
        XCTAssertFalse(store.headGestures)
        XCTAssertFalse(store.captureButton)
        XCTAssertFalse(BuildFlavor.standard.allowsExperimental)
        XCTAssertTrue(BuildFlavor.owner.allowsExperimental)
    }
}
