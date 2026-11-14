// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class V1PathTests: XCTestCase {
    private var context: FastModeRouter.Context {
        FastModeRouter.Context(
            fastMode: false,
            isPro: true,
            bots: AssistantRoster.seed,
            instantReady: false,
            clipEnabled: false
        )
    }

    func testAskIndyAboutKeepsTheRestOfTheSentence() {
        let addressed = AssistantRoster.address(in: "ask Indy about the gate", bots: AssistantRoster.seed)
        XCTAssertEqual(addressed.bot.name, "Indy")
        XCTAssertEqual(addressed.remainder, "about the gate")
        XCTAssertTrue(addressed.explicit)
        guard case .relay(let turn) = FastModeRouter.rules("ask Indy about the gate", context: context) else {
            return XCTFail("Named assistant should go to the relay")
        }
        XCTAssertEqual(turn.targetBot, "Indy")
        XCTAssertEqual(turn.text, "about the gate")
        XCTAssertEqual(turn.intent, "message")
    }

    func testAskIndyToStripsTheVerb() {
        let direct = AssistantRoster.address(in: "ask Indy to book a table", bots: AssistantRoster.seed)
        XCTAssertEqual(direct.bot.name, "Indy")
        XCTAssertEqual(direct.remainder, "book a table")
        let afterWakeComma = AssistantRoster.address(in: ", ask Indy to book a table", bots: AssistantRoster.seed)
        XCTAssertEqual(afterWakeComma.bot.name, "Indy")
        XCTAssertEqual(afterWakeComma.remainder, "book a table")
    }

    func testLongestBotNameWins() {
        let addressed = AssistantRoster.address(in: "ask Fire Fox to check the orders", bots: AssistantRoster.seed)
        XCTAssertEqual(addressed.bot.name, "Fire Fox")
        XCTAssertEqual(addressed.remainder, "check the orders")
    }

    func testUnnamedUtteranceStaysWithTheDefaultBot() {
        guard case .relay(let turn) = FastModeRouter.rules("book a table for seven", context: context) else {
            return XCTFail("A task with no name should still reach the default bot")
        }
        XCTAssertEqual(turn.targetBot, "Fire Fox")
        XCTAssertEqual(turn.text, "book a table for seven")
    }

    func testDictationCleanupDropsFillers() {
        XCTAssertEqual(DictationCleanup.clean("um what time is it"), "What time is it.")
        XCTAssertEqual(DictationCleanup.clean("What do you see?"), "What do you see?")
    }

    func testTempleTapTalksAndBandTapIsMarked() {
        let temple = GestureMap.interpret(GestureSignal(source: .temple, kind: .select))
        XCTAssertEqual(temple.gesture, .talkOrConfirm)
        XCTAssertFalse(temple.sawBand)
        let band = GestureMap.interpret(GestureSignal(source: .band, kind: .select))
        XCTAssertEqual(band.gesture, .talkOrConfirm)
        XCTAssertTrue(band.sawBand)
    }

    func testCaptureButtonLooksAndHoldTakesANote() {
        let look = GestureMap.interpret(GestureSignal(source: .captureButton, kind: .capture(.short)))
        XCTAssertEqual(look.gesture, .look)
        let note = GestureMap.interpret(GestureSignal(source: .captureButton, kind: .capture(.hold)))
        XCTAssertEqual(note.gesture, .note)
    }

    func testDragDirection() {
        let next = GestureMap.interpret(GestureSignal(source: .bandDrag, kind: .dragEnded(dx: 20)))
        XCTAssertEqual(next.gesture, .next)
        XCTAssertTrue(next.sawBand)
        let dismiss = GestureMap.interpret(GestureSignal(source: .temple, kind: .dragEnded(dx: -20)))
        XCTAssertEqual(dismiss.gesture, .dismiss)
    }
}
