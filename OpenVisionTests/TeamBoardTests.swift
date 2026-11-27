// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class TeamBoardTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func board() -> TeamBoard { TeamBoard(roster: AssistantRoster.seed) }
    private func status(_ board: TeamBoard, _ name: String) -> TeamBoard.Status? {
        board.members.first { $0.name == name }?.status
    }

    // MARK: - The roster

    func testTheBoardHasACardForEachAssistantInOrder() {
        XCTAssertEqual(board().members.map(\.name), ["Fire Fox", "Indy", "Driver", "Rally"])
        XCTAssertEqual(board().members.map(\.isDefault), [true, false, false, false])
        XCTAssertTrue(board().members.allSatisfy { $0.status == .ready })
    }

    func testARenamedAssistantKeepsItsStatusAndARemovedOneGoes() {
        var board = board()
        board.asked("Indy", task: "check the invoice", at: at(0))
        var roster = AssistantRoster.seed
        roster[1].name = "Indiana"
        roster.removeLast()
        board.sync(roster: roster)
        XCTAssertEqual(board.members.map(\.name), ["Fire Fox", "Indiana", "Driver"])
        XCTAssertEqual(status(board, "Indiana"), .working(task: "check the invoice", since: at(0)))
    }

    func testTwoAssistantsWithTheSameIdShareOneCard() {
        var roster = AssistantRoster.seed
        roster[2].id = roster[1].id
        XCTAssertEqual(TeamBoard(roster: roster).members.count, 3)
    }

    func testMonograms() {
        XCTAssertEqual(board().members.map(\.monogram), ["FF", "I", "D", "R"])
        XCTAssertEqual(TeamBoard.Member(id: "x", name: "r2-d2 unit", isDefault: false).monogram, "RD")
        XCTAssertEqual(TeamBoard.Member(id: "x", name: "…", isDefault: false).monogram, "?")
    }

    // MARK: - Asking and answering

    func testAnAskMarksThatAssistantAsWorking() {
        var board = board()
        board.asked("indy", task: "check the\nsupplier invoice", at: at(0))
        XCTAssertEqual(status(board, "Indy"), .working(task: "check the supplier invoice", since: at(0)))
        XCTAssertEqual(status(board, "Rally"), .ready)
        XCTAssertEqual(board.working?.name, "Indy")
    }

    func testAnAskWithNoNameGoesToTheDefaultAssistant() {
        var board = board()
        board.asked(nil, task: "what's next", at: at(0))
        XCTAssertEqual(board.working?.name, "Fire Fox")
        board.settled("", at: at(1))
        XCTAssertNil(board.working)
    }

    func testAskingEveryoneMarksEveryone() {
        var board = board()
        board.asked(AssistantBot.allBots, task: "status", at: at(0))
        XCTAssertTrue(board.members.allSatisfy(\.isWorking))
        XCTAssertEqual(board.workingNames, "everyone")
    }

    func testANameTheRosterDoesNotHaveChangesNoCard() {
        var board = board()
        board.asked("Scout", task: "status", at: at(0))
        board.answered(by: "Scout", text: "Here.", at: at(1))
        XCTAssertEqual(board, self.board())
    }

    func testAReplyMarksItsAuthorAsAnsweredAndTheRestKeepWorking() {
        var board = board()
        board.asked(AssistantBot.allBots, task: "status", at: at(0))
        board.answered(by: "Rally", text: "All clear.", at: at(4))
        XCTAssertEqual(status(board, "Rally"), .answered(text: "All clear.", at: at(4)))
        XCTAssertEqual(board.workingNames, "3 assistants")
    }

    func testWhenTheAskIsOverAnyoneWhoDidNotAnswerGoesBackToWhatWasLastTrue() {
        var board = board()
        board.answered(by: "Indy", text: "Filed.", at: at(0))
        board.asked(AssistantBot.allBots, task: "status", at: at(10))
        board.answered(by: "Rally", text: "All clear.", at: at(14))
        board.settled(AssistantBot.allBots, at: at(20))
        XCTAssertEqual(status(board, "Rally"), .answered(text: "All clear.", at: at(14)))
        XCTAssertEqual(status(board, "Indy"), .answered(text: "Filed.", at: at(0)))
        XCTAssertEqual(status(board, "Driver"), .ready)
        XCTAssertNil(board.working)
    }

    func testAnEmptyReplyIsNotAnAnswer() {
        var board = board()
        board.asked("Indy", task: "status", at: at(0))
        board.answered(by: "Indy", text: "  ", at: at(1))
        XCTAssertEqual(status(board, "Indy"), .working(task: "status", since: at(0)))
    }

    func testAFailureIsShownOnlyOnAssistantsThatWereStillWorking() {
        var board = board()
        board.asked(AssistantBot.allBots, task: "status", at: at(0))
        board.answered(by: "Rally", text: "All clear.", at: at(4))
        board.failed(AssistantBot.allBots, reason: "No connection.", at: at(9))
        XCTAssertEqual(status(board, "Rally"), .answered(text: "All clear.", at: at(4)))
        XCTAssertEqual(status(board, "Indy"), .failed(reason: "No connection.", at: at(9)))
    }

    func testAReplyWithNoNameBelongsToTheDefaultAssistant() {
        var board = board()
        board.asked(nil, task: "status", at: at(0))
        board.answered(by: "", text: "Done.", at: at(2))
        XCTAssertEqual(status(board, "Fire Fox"), .answered(text: "Done.", at: at(2)))
    }

    // MARK: - Alerts

    func testAnAlertShowsOnTheCardOfWhoSentIt() {
        var board = board()
        board.alerted(by: "Driver", text: "Build finished.", urgent: false, at: at(0))
        XCTAssertEqual(status(board, "Driver"), .alerted(text: "Build finished.", at: at(0), urgent: false))
    }

    func testAnAlertDoesNotHideWorkInProgressButIsKept() {
        var board = board()
        board.asked("Driver", task: "deploy", at: at(0))
        board.alerted(by: "Driver", text: "Tests passed.", urgent: true, at: at(5))
        XCTAssertEqual(status(board, "Driver"), .working(task: "deploy", since: at(0)))
        XCTAssertEqual(board.members[2].events.map(\.kind), [.alerted, .asked])
    }

    func testAnAlertThatArrivedDuringWorkShowsOnceTheWorkIsWithdrawn() {
        var board = board()
        board.asked("Driver", task: "deploy", at: at(0))
        board.alerted(by: "Driver", text: "Tests passed.", urgent: false, at: at(5))
        board.settled("Driver", at: at(6))
        XCTAssertEqual(status(board, "Driver"), .alerted(text: "Tests passed.", at: at(5), urgent: false))
    }

    // MARK: - History

    func testEventsAreNewestFirstWithUniqueIdsAndALimit() {
        var board = board()
        for n in 0..<20 {
            board.asked("Indy", task: "task \(n)", at: at(Double(n)))
            board.answered(by: "Indy", text: "done \(n)", at: at(Double(n) + 0.5))
        }
        let events = board.members[1].events
        XCTAssertEqual(events.count, TeamBoard.eventLimit)
        XCTAssertEqual(events.first?.text, "done 19")
        XCTAssertEqual(Set(events.map(\.id)).count, events.count)
        XCTAssertEqual(events.map(\.at), events.map(\.at).sorted(by: >))
    }

    // MARK: - Who is working

    func testTheLiveStateNamesWhoeverHasWaitedLongest() {
        var board = board()
        board.asked("Rally", task: "a", at: at(5))
        board.asked("Indy", task: "b", at: at(2))
        XCTAssertEqual(board.working?.name, "Indy")
        XCTAssertEqual(board.workingNames, "Indy and Rally")
    }

    func testEveryoneOnATeamOfTwoIsNamed() {
        var board = TeamBoard(roster: Array(AssistantRoster.seed.prefix(2)))
        board.asked(AssistantBot.allBots, task: "status", at: at(0))
        XCTAssertEqual(board.workingNames, "Fire Fox and Indy")
        XCTAssertNil(self.board().workingNames)
    }

    // MARK: - Words

    func testTheLineUnderAName() {
        XCTAssertEqual(TeamBoard.line(for: .ready, now: at(0)), "Ready")
        XCTAssertEqual(TeamBoard.line(for: .working(task: "check the invoice", since: at(0)), now: at(9)), "Working on: check the invoice")
        XCTAssertEqual(TeamBoard.line(for: .working(task: "", since: at(0)), now: at(9)), "Working")
        XCTAssertEqual(TeamBoard.line(for: .answered(text: "All clear.", at: at(0)), now: at(130)), "Answered 2 minutes ago: All clear.")
        XCTAssertEqual(TeamBoard.line(for: .alerted(text: "Build finished.", at: at(0), urgent: false), now: at(10)), "Sent just now: Build finished.")
        XCTAssertEqual(TeamBoard.line(for: .alerted(text: "Leak.", at: at(0), urgent: true), now: at(3700)), "Urgent 1 hour ago: Leak.")
        XCTAssertEqual(TeamBoard.line(for: .failed(reason: "No connection.", at: at(0)), now: at(61)), "No answer 1 minute ago. No connection.")
    }

    func testVoiceOverHearsTheNameTheLineAndHowLong() {
        var board = board()
        board.asked("Indy", task: "check the invoice", at: at(0))
        XCTAssertEqual(TeamBoard.spoken(for: board.members[1], now: at(20)), "Indy. Working on: check the invoice. for 20 seconds")
        XCTAssertEqual(TeamBoard.spoken(for: board.members[0], now: at(20)), "Fire Fox. Ready")
    }

    func testWhatToSayToReachAnAssistant() {
        let board = board()
        XCTAssertEqual(TeamBoard.example(for: board.members[0], wakeWord: "Hey Phoenix"), "“Hey Phoenix, what should I do next?”")
        XCTAssertEqual(TeamBoard.example(for: board.members[1], wakeWord: "Friday"), "“Friday, ask Indy to check on it.”")
        XCTAssertEqual(TeamBoard.exampleForEveryone(wakeWord: "Hey Phoenix"), "“Hey Phoenix, all hands.”")
    }

    func testTheExamplesAreSentencesTheRouterSendsWhereTheySay() {
        // The words after the wake word, as the router would get them.
        let named = AssistantRoster.address(in: "ask Indy to check on it.", bots: AssistantRoster.seed)
        XCTAssertEqual(named.bot.name, "Indy")
        XCTAssertTrue(named.explicit)
    }

    func testEveryKindOfEventHasAHeading() {
        for kind in [TeamBoard.Event.Kind.asked, .answered, .alerted, .failed] {
            XCTAssertFalse(kind.label.isEmpty)
        }
    }

    func testDurations() {
        XCTAssertEqual(TeamBoard.duration(0), "0 seconds")
        XCTAssertEqual(TeamBoard.duration(1), "1 second")
        XCTAssertEqual(TeamBoard.duration(59.9), "59 seconds")
        XCTAssertEqual(TeamBoard.duration(60), "1 minute")
        XCTAssertEqual(TeamBoard.duration(7200), "2 hours")
        XCTAssertEqual(TeamBoard.duration(86_400 * 3), "3 days")
        XCTAssertEqual(TeamBoard.duration(-5), "0 seconds")
        XCTAssertEqual(TeamBoard.ago(at(0), now: at(-5)), "just now", "A clock that moved back is not a crash")
    }

    func testALongReportIsCutAtAWord() {
        let report = Array(repeating: "valve", count: 60).joined(separator: " ")
        let short = TeamBoard.short(report)
        XCTAssertLessThanOrEqual(short.count, 121)
        XCTAssertTrue(short.hasSuffix("valve…"))
        XCTAssertEqual(TeamBoard.short("Done."), "Done.")
    }
}
