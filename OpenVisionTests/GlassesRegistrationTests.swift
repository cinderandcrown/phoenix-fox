// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class GlassesRegistrationTests: XCTestCase {

    // MARK: - Preparation

    func testPreparationNamesTheVersionsAndDeveloperMode() {
        let text = GlassesPreparation.steps.joined(separator: " ")
        XCTAssertTrue(text.contains("\(GlassesRequirements.metaAIVersion)"))
        XCTAssertTrue(text.contains("\(GlassesRequirements.glassesVersion)"))
        XCTAssertTrue(text.contains("Developer Mode"))
        XCTAssertTrue(GlassesPreparation.developerModePath.contains("App Info"))
        XCTAssertFalse(GlassesPreparation.reason.isEmpty)
    }

    func testTheGlassesStepNamesTheSamePreparation() {
        XCTAssertEqual(OnboardingStep.glasses.preparation, GlassesPreparation.steps)
        XCTAssertTrue(OnboardingStep.glasses.summary.contains("Developer Mode"))
        XCTAssertTrue(OnboardingStep.glasses.summary.contains("pair"))
        for step in OnboardingStep.allCases where step != .glasses {
            XCTAssertTrue(step.preparation.isEmpty)
        }
    }

    func testTheGlassesButtonFollowsTheConnection() {
        XCTAssertEqual(OnboardingStep.glassesButton(connected: true, stall: nil), "Continue")
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: nil), "Open Meta AI")
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: .returnedUnconnected), "Try again")
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: .badBuild), "Open Meta AI")
    }

    // MARK: - Stall copy

    func testComingBackUnconnectedNamesDeveloperModeAndTheUpdates() {
        let stall = RegistrationStall.returnedUnconnected
        XCTAssertEqual(stall.title, "Meta AI did not connect your glasses")
        XCTAssertTrue(stall.explanation.contains("Internal error"))
        XCTAssertTrue(stall.canRetry)
        let steps = stall.steps.joined(separator: " ")
        XCTAssertTrue(steps.contains("Developer Mode"))
        XCTAssertTrue(steps.contains("\(GlassesRequirements.metaAIVersion)"))
        XCTAssertTrue(steps.contains("\(GlassesRequirements.glassesVersion)"))
        XCTAssertTrue(steps.contains("Close Meta AI completely"))
        XCTAssertTrue(steps.contains("try again"))
    }

    func testARefusedAnswerKeepsTheToolkitsWords() {
        let stall = RegistrationStall.refused("The operation could not be completed")
        XCTAssertTrue(stall.explanation.contains("The operation could not be completed."))
        XCTAssertTrue(stall.canRetry)
    }

    func testABadBuildCannotBeRetriedOnThisPhone() {
        XCTAssertFalse(RegistrationStall.badBuild.canRetry)
        XCTAssertFalse(RegistrationStall.notRunning("The glasses connection is not running.").canRetry)
        XCTAssertTrue(RegistrationStall.notInstalled.canRetry)
        XCTAssertTrue(RegistrationStall.offline.canRetry)
        XCTAssertTrue(RegistrationStall.didNotOpen.canRetry)
    }

    func testNumberedStepsAreSpokenInOrder() {
        let steps = ["First.", "Second."]
        XCTAssertEqual(NumberedStep.spoken(0, of: steps), "Step 1 of 2. First.")
        XCTAssertEqual(NumberedStep.spoken(1, of: steps), "Step 2 of 2. Second.")
    }

    // MARK: - One try

    func testATryThatNeverLeavesTheAppIsADidNotOpen() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        XCTAssertTrue(attempt.isWorking)
        let wait = attempt.handedOff()
        XCTAssertEqual(wait?.kind, .forMetaAIToOpen)
        attempt.waited(wait!)
        XCTAssertEqual(attempt.stall, .didNotOpen)
        XCTAssertFalse(attempt.isWorking)
    }

    func testComingBackWithoutAConnectionIsAReturnedUnconnected() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        _ = attempt.handedOff()
        attempt.enteredBackground()
        let wait = attempt.becameActive()
        XCTAssertEqual(wait?.kind, .forAnswer)
        attempt.waited(wait!)
        XCTAssertEqual(attempt.stall, .returnedUnconnected)
    }

    func testALinkThatArrivesWhileConfirmingCanStillFail() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        _ = attempt.handedOff()
        attempt.enteredBackground()
        _ = attempt.becameActive()
        attempt.answerBegan()
        let wait = attempt.answerEnded(failure: "Internal error")
        XCTAssertNil(wait)
        XCTAssertEqual(attempt.stall, .refused("Internal error"))
        XCTAssertTrue(attempt.answerReceived)
    }

    func testRegisteringClearsTheTrouble() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        attempt.failed(.returnedUnconnected)
        attempt.registered()
        XCTAssertNil(attempt.stall)
        XCTAssertFalse(attempt.isWorking)
    }

    func testAnOldWaitIsIgnored() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        let wait = attempt.handedOff()!
        attempt.begin()
        attempt.waited(wait)
        XCTAssertNil(attempt.stall)
        XCTAssertTrue(attempt.isWorking)
    }

    func testTheDetailsHoldNoSecrets() {
        var attempt = RegistrationAttempt()
        attempt.begin()
        attempt.enteredBackground()
        let line = attempt.details(stage: .available)
        XCTAssertTrue(line.contains("Meta AI opened: yes"))
        XCTAssertTrue(line.contains("Answer from Meta AI: no"))
        XCTAssertTrue(line.contains("available"))
        XCTAssertFalse(line.contains("token"))
        XCTAssertFalse(line.contains("@"))
        XCTAssertFalse(line.contains("http"))
    }
}
