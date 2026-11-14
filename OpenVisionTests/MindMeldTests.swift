// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class MindMeldTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour))!
    }

    func testAskIndyGoesToThatBot() {
        let route = FastModeRouter.rules("ask Indy about the gate", context: context())
        guard case .relay(let turn) = route else {
            return XCTFail("expected a relay turn, got \(route)")
        }
        XCTAssertEqual(turn.targetBot, "Indy")
        XCTAssertTrue(turn.text.localizedCaseInsensitiveContains("gate"))
        XCTAssertEqual(turn.intent, "message")
    }

    func testAllHandsNeedsTheNamedBots() {
        let route = FastModeRouter.rules("status report", context: context())
        guard case .relay(let turn) = route else {
            return XCTFail("expected all-hands relay, got \(route)")
        }
        XCTAssertEqual(turn.targetBot, AssistantBot.allBots)
        XCTAssertEqual(turn.intent, "status")
    }

    func testAnticipateUsesTheLastThingHeSaid() {
        let episodes = [MindEpisode(at: date(hour: 15), said: "the gate code changed", heard: nil, bot: nil, saw: nil)]
        let suggestion = MindMeldPlanner.anticipate(
            episodes: episodes,
            now: date(hour: 15),
            bots: ["Fire Fox", "Indy", "Driver", "Rally"],
            logging: true,
            calendar: calendar
        )
        XCTAssertTrue(suggestion.spoken.localizedCaseInsensitiveContains("gate"))
        XCTAssertTrue(suggestion.ask.localizedCaseInsensitiveContains("gate"))
    }

    func testMorningWithAnEmptyLogNamesABotAndDoesNotInventAMemory() {
        let suggestion = MindMeldPlanner.anticipate(
            episodes: [],
            now: date(hour: 8),
            bots: ["Fire Fox", "Indy"],
            logging: false,
            calendar: calendar
        )
        XCTAssertEqual(suggestion.bot, "Fire Fox")
        XCTAssertTrue(suggestion.spoken.localizedCaseInsensitiveContains("mind meld is off"))
        XCTAssertTrue(suggestion.ask.localizedCaseInsensitiveContains("morning brief"))
    }

    func testSeenRecallRefusesACameraRoll() {
        let line = MindMeldPlanner.recallSeen([], logging: true)
        XCTAssertTrue(line.localizedCaseInsensitiveContains("capture light") || line.localizedCaseInsensitiveContains("look"))
        XCTAssertFalse(line.localizedCaseInsensitiveContains("jpeg"))
    }

    func testHandoffUsesThePendingAskWhenHeSaysThat() {
        let pending = MindSuggestion(bot: "Indy", ask: "Check the gate code.", spoken: "Say do that.")
        let ask = MindMeldPlanner.handoffAsk(pending: pending, episodes: [], explicit: "that")
        XCTAssertEqual(ask, "Check the gate code.")
    }

    func testHaveIndyHandleThatIsAHandoff() {
        let route = FastModeRouter.rules("have Indy handle that", context: context())
        guard case .mind(.handoff(let bot, let ask)) = route else {
            return XCTFail("expected a handoff, got \(route)")
        }
        XCTAssertEqual(bot, "Indy")
        XCTAssertEqual(ask, nil)
    }

    func testMindMeldConsentPhrases() {
        guard case .mind(.consent(true)) = FastModeRouter.rules("mind meld on", context: context()) else {
            return XCTFail("on")
        }
        guard case .mind(.consent(false)) = FastModeRouter.rules("mind meld off", context: context()) else {
            return XCTFail("off")
        }
    }

    private func context() -> FastModeRouter.Context {
        FastModeRouter.Context(
            fastMode: true,
            isPro: true,
            bots: AssistantRoster.seed,
            instantReady: true,
            clipEnabled: false
        )
    }
}
