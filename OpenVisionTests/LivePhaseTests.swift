// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class LivePhaseTests: XCTestCase {
    private func phase(_ change: (inout LiveSignals) -> Void) -> LivePhase {
        var signals = LiveSignals()
        change(&signals)
        return LivePhase(signals)
    }

    // MARK: - Which phase

    func testTheFourStatesTheOwnerAskedForEachHaveAPhase() {
        XCTAssertEqual(phase { $0.activity = .listening }, .listening)
        XCTAssertEqual(phase { $0.activity = .thinking; $0.cameraOn = true }, .looking)
        XCTAssertEqual(phase { $0.activity = .thinking }, .thinking)
        XCTAssertEqual(phase { $0.activity = .speaking }, .replying)
    }

    func testAtRestItIsReadyOnceTheVoiceHasLoaded() {
        XCTAssertEqual(phase { _ in }, .ready)
        XCTAssertEqual(phase { $0.voiceReady = false }, .gettingReady)
        // With the wake word off there is nothing to load before a tap works.
        XCTAssertEqual(phase { $0.voiceReady = false; $0.wakeWordOn = false }, .ready)
    }

    func testAnAssistantThatHasBeenAskedIsNamed() {
        XCTAssertEqual(phase { $0.activity = .thinking; $0.askedAssistant = "Indy" }, .asking("Indy"))
        XCTAssertEqual(phase { $0.activity = .thinking; $0.askedAssistant = "  " }, .thinking)
        // The name wins over the camera: the photo has been taken and Indy has it.
        XCTAssertEqual(phase { $0.activity = .thinking; $0.askedAssistant = "Indy"; $0.cameraOn = true }, .asking("Indy"))
    }

    func testAnAssistantIsOnlyNamedWhileJarvisIsWaitingForIt() {
        XCTAssertEqual(phase { $0.activity = .speaking; $0.askedAssistant = "Indy" }, .replying)
        XCTAssertEqual(phase { $0.activity = .listening; $0.askedAssistant = "Indy" }, .listening)
        XCTAssertEqual(phase { $0.askedAssistant = "Indy" }, .ready)
    }

    func testAToolShowsWhatItIsDoing() {
        XCTAssertEqual(phase { $0.activity = .usingTool; $0.tool = "Setting a timer" }, .working("Setting a timer"))
        XCTAssertEqual(phase { $0.activity = .usingTool }, .working(nil))
        XCTAssertEqual(phase { $0.activity = .usingTool; $0.cameraOn = true }, .looking)
    }

    func testSpeakingAndListeningAreNeverHiddenByTheCamera() {
        XCTAssertEqual(phase { $0.activity = .speaking; $0.cameraOn = true }, .replying)
        XCTAssertEqual(phase { $0.activity = .listening; $0.cameraOn = true }, .listening)
        XCTAssertEqual(phase { $0.activity = .liveVideo; $0.cameraOn = true }, .liveVideo)
    }

    // MARK: - Words

    private let everyPhase: [LivePhase] = [
        .gettingReady, .ready, .connecting, .listening, .looking, .thinking,
        .asking("Indy"), .working("Setting a timer"), .working(nil), .replying, .liveVideo,
    ]

    func testEveryPhaseHasAShortTitleAHintAndASymbol() {
        for phase in everyPhase {
            XCTAssertFalse(phase.title.isEmpty)
            XCTAssertLessThanOrEqual(phase.title.split(separator: " ").count, 3, phase.title)
            XCTAssertFalse(phase.title.hasSuffix("..."), "A title is a word, not a spinner: \(phase.title)")
            XCTAssertFalse(phase.hint(LiveSignals()).isEmpty)
            XCTAssertFalse(phase.symbol.isEmpty)
        }
    }

    func testTheReadyHintNamesTheWakeWordTheOwnerChose() {
        var signals = LiveSignals()
        signals.wakeWord = "Friday"
        XCTAssertEqual(LivePhase.ready.hint(signals), "Say “Friday” or tap.")
        signals.wakeWordOn = false
        XCTAssertEqual(LivePhase.ready.hint(signals), "Tap to talk.")
    }

    func testTheReplyingHintSaysHowToInterrupt() {
        // Speech alone does not stop an answer, because the microphone also hears the
        // answer. The wake word does, so the hint names it.
        XCTAssertEqual(LivePhase.replying.hint(LiveSignals()), "Say “Hey Phoenix, stop” or tap.")
        XCTAssertEqual(LivePhase.replying.hint(LiveSignals(wakeWord: "Friday")), "Say “Friday, stop” or tap.")
    }

    // MARK: - The tap

    func testATapWhileReplyingStopsTheAnswerAndDoesNotEndTheConversation() {
        XCTAssertEqual(LivePhase.replying.tap, .stopTalking)
    }

    func testATapAtRestStartsAndATapMidTurnEnds() {
        XCTAssertEqual(LivePhase.ready.tap, .start)
        XCTAssertEqual(LivePhase.gettingReady.tap, .start)
        for phase in [LivePhase.listening, .thinking, .looking, .asking("Indy"), .working(nil), .connecting, .liveVideo] {
            XCTAssertEqual(phase.tap, .end, phase.title)
        }
    }

    // MARK: - The orb

    func testEachOfTheFourStatesMovesTheOrbItsOwnWay() {
        XCTAssertEqual(LivePhase.ready.mood, .resting)
        XCTAssertEqual(LivePhase.listening.mood, .listening)
        XCTAssertEqual(LivePhase.thinking.mood, .thinking)
        XCTAssertEqual(LivePhase.looking.mood, .thinking)
        XCTAssertEqual(LivePhase.replying.mood, .replying)
    }

    func testOnlyWaitingPhasesAreBusy() {
        XCTAssertTrue(LivePhase.thinking.isBusy)
        XCTAssertTrue(LivePhase.asking("Indy").isBusy)
        XCTAssertFalse(LivePhase.ready.isBusy)
        XCTAssertFalse(LivePhase.listening.isBusy)
        XCTAssertFalse(LivePhase.replying.isBusy)
    }

    // MARK: - VoiceOver

    func testTheStageIsOneElementThatSaysThePhaseAndWhatATapDoes() {
        let description = StageDescription(phase: .listening, signals: LiveSignals())
        XCTAssertEqual(description.label, "Phoenix")
        XCTAssertEqual(description.value, "Listening. Go ahead.")
        XCTAssertEqual(description.hint, "Ends the conversation.")
    }

    func testVoiceOverIsToldWhenTheCameraIsOn() {
        var signals = LiveSignals()
        signals.cameraOn = true
        let description = StageDescription(phase: .looking, signals: signals)
        XCTAssertEqual(description.value, "Looking. Through your glasses. The camera on your glasses is on.")
    }

    func testTheSpokenValueHasNoDoubledFullStops() {
        for phase in everyPhase {
            let value = StageDescription(phase: phase, signals: LiveSignals()).value
            XCTAssertFalse(value.contains(".."), value)
        }
    }

    // MARK: - The glasses

    func testTheGlassesChip() {
        XCTAssertEqual(GlassesStatus(registered: false, devicesInReach: 0, cameraOn: false), .notConnected)
        XCTAssertEqual(GlassesStatus(registered: true, devicesInReach: 0, cameraOn: false), .away)
        // Listed but not linked ≠ ready (DAT PermissionError.noDeviceWithConnection).
        XCTAssertEqual(GlassesStatus(registered: true, devicesInReach: 1, cameraOn: false, linkConnected: false), .away)
        XCTAssertEqual(GlassesStatus(registered: true, devicesInReach: 1, cameraOn: false, linkConnected: true), .ready)
        XCTAssertEqual(GlassesStatus(registered: true, devicesInReach: 1, cameraOn: true, linkConnected: true), .cameraOn)
        // Without a connection there is no camera to be on.
        XCTAssertEqual(GlassesStatus(registered: false, devicesInReach: 0, cameraOn: true), .notConnected)
        for status in [GlassesStatus.notConnected, .away, .ready, .cameraOn] {
            XCTAssertLessThanOrEqual(status.title.split(separator: " ").count, 2)
            XCTAssertTrue(status.spoken.hasSuffix("."))
        }
    }

    // MARK: - Haptics

    func testATurnHasThreeBeats() {
        XCTAssertEqual(HapticCue.cue(from: .ready, to: .listening), .listening)
        XCTAssertEqual(HapticCue.cue(from: .listening, to: .thinking), .heard)
        XCTAssertEqual(HapticCue.cue(from: .listening, to: .asking("Indy")), .heard)
        XCTAssertEqual(HapticCue.cue(from: .listening, to: .looking), .heard)
        XCTAssertEqual(HapticCue.cue(from: .thinking, to: .replying), .replying)
    }

    func testNothingIsFeltWhenNothingChanged() {
        XCTAssertNil(HapticCue.cue(from: .thinking, to: .thinking))
        XCTAssertNil(HapticCue.cue(from: .asking("Indy"), to: .asking("Indy")))
    }

    func testThinkingThatMovesBetweenItsOwnPhasesIsFeltOnce() {
        XCTAssertNil(HapticCue.cue(from: .thinking, to: .looking))
        XCTAssertNil(HapticCue.cue(from: .thinking, to: .asking("Indy")))
        XCTAssertNil(HapticCue.cue(from: .asking("Indy"), to: .working(nil)))
    }

    func testTheMicrophoneReopeningAfterAnAnswerIsNotFelt() {
        XCTAssertNil(HapticCue.cue(from: .replying, to: .listening))
    }

    func testGoingBackToRestIsSilent() {
        XCTAssertNil(HapticCue.cue(from: .replying, to: .ready))
        XCTAssertNil(HapticCue.cue(from: .listening, to: .ready))
        XCTAssertNil(HapticCue.cue(from: .ready, to: .connecting))
    }

    func testTheCameraComingOnIsFeltAndGoingOffIsNot() {
        XCTAssertEqual(HapticCue.cue(cameraWasOn: false, cameraIsOn: true), .cameraOn)
        XCTAssertNil(HapticCue.cue(cameraWasOn: true, cameraIsOn: false))
        XCTAssertNil(HapticCue.cue(cameraWasOn: true, cameraIsOn: true))
    }
}
