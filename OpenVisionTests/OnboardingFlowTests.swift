// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class OnboardingFlowTests: XCTestCase {
    // MARK: - Steps

    func testTheStepsRunInOrderFromWelcomeToReady() {
        var steps: [OnboardingStep] = [.welcome]
        while let next = steps.last?.next { steps.append(next) }
        XCTAssertEqual(steps, [.welcome, .glasses, .permissions, .assistants, .ready])
        XCTAssertNil(OnboardingStep.welcome.previous)
        XCTAssertNil(OnboardingStep.ready.next)
        XCTAssertEqual(OnboardingStep.ready.previous, .assistants)
    }

    func testProgressCountsFromOne() {
        XCTAssertEqual(OnboardingStep.welcome.progress, "Step 1 of 5")
        XCTAssertEqual(OnboardingStep.ready.progress, "Step 5 of 5")
    }

    func testASavedStepIsRestoredAndABadNumberStillLandsOnAStep() {
        for step in OnboardingStep.allCases {
            XCTAssertEqual(OnboardingStep.restored(step.rawValue), step)
        }
        XCTAssertEqual(OnboardingStep.restored(-3), .welcome)
        XCTAssertEqual(OnboardingStep.restored(99), .ready)
    }

    func testEveryStepHasATitleASummaryAndASymbol() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertLessThanOrEqual(step.title.split(separator: " ").count, 4, step.title)
            XCTAssertFalse(step.summary.isEmpty)
            XCTAssertFalse(step.symbol.isEmpty)
        }
    }

    func testEveryStepWithSomethingToSetUpCanBeSkipped() {
        XCTAssertNil(OnboardingStep.welcome.skipTitle)
        XCTAssertNil(OnboardingStep.ready.skipTitle)
        for step in [OnboardingStep.glasses, .permissions, .assistants] {
            XCTAssertNotNil(step.skipTitle, step.title)
        }
    }

    func testTheGlassesStepPromisesTheCaptureLight() {
        let promise = OnboardingStep.glasses.promise ?? ""
        XCTAssertTrue(promise.contains("capture light"))
        XCTAssertTrue(promise.contains("only when you ask"))
    }

    func testTheGlassesStepTellsTheWearerWhatToDoInMetaAIFirst() {
        XCTAssertFalse(OnboardingStep.glasses.preparation.isEmpty)
        XCTAssertTrue(OnboardingStep.glasses.summary.contains("Developer Mode"))
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: nil), "Open Meta AI")
        XCTAssertEqual(OnboardingStep.glassesButton(connected: false, stall: .returnedUnconnected), "Try again")
    }

    func testTheAssistantsStepSaysWhereTheTokenIsKept() {
        XCTAssertEqual(OnboardingStep.assistants.promise?.contains("Keychain"), true)
    }

    func testTheWordsArePlain() {
        // Words a person setting up glasses should not have to know.
        let jargon = ["register", "authorize", "authenticate", "configure", "endpoint", "bearer", "backend", "SDK", "API", "LLM", "token "]
        let allowed = "relay token"
        for step in OnboardingStep.allCases {
            let text = [step.title, step.summary, step.promise ?? "", step.skipTitle ?? ""].joined(separator: " ")
            for word in jargon {
                let stripped = text.replacingOccurrences(of: allowed, with: "")
                XCTAssertFalse(stripped.localizedCaseInsensitiveContains(word), "“\(word)” in \(step)")
            }
        }
        for permission in OnboardingPermission.allCases {
            for word in jargon {
                XCTAssertFalse(permission.reason.localizedCaseInsensitiveContains(word), "“\(word)” in \(permission)")
            }
        }
    }

    // MARK: - Permissions

    func testOnlyThreePermissionsAreAskedForUpFront() {
        XCTAssertEqual(OnboardingPermission.allCases, [.microphone, .speech, .notifications])
    }

    func testEachPermissionSaysWhyInOneOrTwoSentences() {
        for permission in OnboardingPermission.allCases {
            XCTAssertTrue(permission.reason.hasPrefix("So "), "A reason starts with what it is for: \(permission.reason)")
            XCTAssertLessThanOrEqual(permission.reason.filter { $0 == "." }.count, 2)
        }
    }

    func testNotificationsAreTheOnlyOneVoiceCanDoWithout() {
        XCTAssertTrue(OnboardingPermission.microphone.isNeededForVoice)
        XCTAssertTrue(OnboardingPermission.speech.isNeededForVoice)
        XCTAssertFalse(OnboardingPermission.notifications.isNeededForVoice)
        XCTAssertTrue(OnboardingPermission.notifications.reason.contains("You can leave this off."))
    }

    func testTheButtonFollowsTheAnswer() {
        let permission = OnboardingPermission.microphone
        XCTAssertEqual(permission.buttonTitle(.notAsked), "Allow")
        XCTAssertNil(permission.buttonTitle(.allowed))
        XCTAssertEqual(permission.buttonTitle(.denied), "Open Settings")
        XCTAssertNil(permission.status(.notAsked))
        XCTAssertEqual(permission.status(.allowed), "Allowed")
        XCTAssertEqual(permission.status(.denied), "Turned off. You can turn it on in the Settings app.")
    }

    func testVoiceOverHearsTheNameTheAnswerAndTheReason() {
        XCTAssertEqual(
            OnboardingPermission.speech.spoken(.allowed),
            "Speech recognition. Allowed. So Jarvis can hear its wake word and turn what you say into text."
        )
        XCTAssertTrue(OnboardingPermission.speech.spoken(.notAsked).hasPrefix("Speech recognition. So Jarvis"))
    }

    // MARK: - Who answers

    func testASavedRelayMeansTheAssistantsAnswer() {
        XCTAssertEqual(StartingBrain.choose(relayReady: true, currentIsAssistants: true, currentReady: true, onDeviceReady: true), .assistants)
    }

    func testAnotherAIThatAlreadyWorksIsLeftAlone() {
        XCTAssertEqual(StartingBrain.choose(relayReady: false, currentIsAssistants: false, currentReady: true, onDeviceReady: true), .keepCurrent)
        // Even when a relay is also saved: the wearer chose the other one.
        XCTAssertEqual(StartingBrain.choose(relayReady: true, currentIsAssistants: false, currentReady: true, onDeviceReady: true), .keepCurrent)
    }

    func testANewWearerWithNothingSetUpStartsOnThePhone() {
        XCTAssertEqual(StartingBrain.choose(relayReady: false, currentIsAssistants: true, currentReady: false, onDeviceReady: true), .onDevice)
        XCTAssertEqual(StartingBrain.choose(relayReady: false, currentIsAssistants: false, currentReady: false, onDeviceReady: true), .onDevice)
    }

    func testAnotherAIThatDoesNotWorkGivesWayToASavedRelay() {
        XCTAssertEqual(StartingBrain.choose(relayReady: true, currentIsAssistants: false, currentReady: false, onDeviceReady: true), .assistants)
    }

    func testWithNothingAtAllTheLastStepSaysSo() {
        XCTAssertEqual(StartingBrain.choose(relayReady: false, currentIsAssistants: true, currentReady: false, onDeviceReady: false), .none)
    }

    // MARK: - The last step

    func testEverythingDone() {
        let summary = OnboardingSummary(glassesConnected: true, microphone: .allowed, speech: .allowed, brain: .assistants, wakeWord: "Jarvis")
        XCTAssertTrue(summary.lines.allSatisfy(\.done))
        XCTAssertTrue(summary.canTalk)
        XCTAssertEqual(summary.tryThis, "Say “Jarvis, what should I do next?”")
    }

    func testWithoutGlassesJarvisStillWorksOnThePhone() {
        let summary = OnboardingSummary(glassesConnected: false, microphone: .allowed, speech: .allowed, brain: .onDevice, wakeWord: "Friday")
        XCTAssertEqual(summary.lines.map(\.done), [false, true, true])
        XCTAssertTrue(summary.canTalk)
        XCTAssertTrue(summary.lines[0].text.contains("this phone's microphone"))
        XCTAssertEqual(summary.tryThis, "Say “Friday, what can you do?”")
    }

    func testADeniedMicrophoneIsSaidPlainlyAndNothingIsPromised() {
        let summary = OnboardingSummary(glassesConnected: true, microphone: .denied, speech: .allowed, brain: .assistants, wakeWord: "Jarvis")
        XCTAssertFalse(summary.canTalk)
        XCTAssertEqual(summary.lines[1].text, "Jarvis cannot hear you yet. Allow the microphone and speech recognition in Settings.")
        XCTAssertTrue(summary.tryThis.hasPrefix("Finish the steps above"))
    }

    func testNoAIIsSaidPlainly() {
        let summary = OnboardingSummary(glassesConnected: true, microphone: .allowed, speech: .allowed, brain: .none, wakeWord: "Jarvis")
        XCTAssertFalse(summary.canTalk)
        XCTAssertEqual(summary.lines[2], .init(id: "brain", done: false, text: "Nothing is set to answer yet. Choose an AI in Settings."))
    }

    func testTheChecklistLinesHaveUniqueIds() {
        let summary = OnboardingSummary(glassesConnected: true, microphone: .allowed, speech: .allowed, brain: .keepCurrent, wakeWord: "Jarvis")
        XCTAssertEqual(Set(summary.lines.map(\.id)).count, summary.lines.count)
    }
}
