// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class SpokenReplyTests: XCTestCase {
    // MARK: - Plain words

    func testPlainSpeechIsLeftAlone() {
        let line = "It's 3.5 miles, about ten minutes. Leave by 4:15."
        XCTAssertEqual(SpokenReply.plain(line), line)
    }

    func testEmphasisMarksAreDroppedAndTheWordsKept() {
        XCTAssertEqual(SpokenReply.plain("The **second** valve is *closed*, not __open__."), "The second valve is closed, not open.")
        XCTAssertEqual(SpokenReply.plain("Run `git status` first."), "Run git status first.")
        XCTAssertEqual(SpokenReply.plain("That was ~~wrong~~ fixed."), "That was wrong fixed.")
    }

    func testUnderscoresAndStarsInsideWordsAndSumsAreKept() {
        XCTAssertEqual(SpokenReply.plain("Set max_retry_count to 3."), "Set max_retry_count to 3.")
        XCTAssertEqual(SpokenReply.plain("That's 4 * 5 * 6."), "That's 4 * 5 * 6.")
    }

    func testAMarkWhoseOtherHalfIsInAnotherPieceIsStillDropped() {
        // A streamed answer is spoken a sentence at a time, so a pair can be split.
        XCTAssertEqual(SpokenReply.plain("**Note: the valve is hot."), "Note: the valve is hot.")
        XCTAssertEqual(SpokenReply.plain("Do not touch it.**"), "Do not touch it.")
        XCTAssertEqual(SpokenReply.plain("Then run `make"), "Then run make.")
    }

    func testHeadingsBulletsAndQuotesBecomeSentences() {
        let written = """
        ## Today
        - Call the supplier
        - Order filters
        > Rally flagged this
        """
        XCTAssertEqual(SpokenReply.plain(written), "Today. Call the supplier. Order filters. Rally flagged this.")
    }

    func testNumberedStepsKeepTheirNumbers() {
        XCTAssertEqual(SpokenReply.plain("1. Shut the valve\n2. Open the drain"), "1. Shut the valve. 2. Open the drain.")
    }

    func testALinkIsSaidAsItsWordsAndABareAddressAsTheSite() {
        XCTAssertEqual(SpokenReply.plain("See [the invoice](https://example.com/inv/42?x=1) for details."), "See the invoice for details.")
        XCTAssertEqual(SpokenReply.plain("It's at https://www.example.com/a/b?c=d."), "It's at example.com.")
        XCTAssertEqual(SpokenReply.plain("Docs: http://docs.example.org/start, then call me."), "Docs: docs.example.org, then call me.")
        XCTAssertEqual(SpokenReply.plain("![a red door](https://example.com/door.jpg)"), "a red door.")
    }

    func testCodeBlocksStayOnThePhone() {
        let written = "Here is the fix.\n```swift\nlet x = 1\n```\nRun it again."
        XCTAssertEqual(SpokenReply.plain(written), "Here is the fix. Run it again.")
    }

    func testATableIsReadAsLists() {
        let written = """
        | Part | Price |
        |------|-------|
        | Filter | $12 |
        """
        XCTAssertEqual(SpokenReply.plain(written), "Part, Price. Filter, $12.")
    }

    func testRulesAreDropped() {
        XCTAssertEqual(SpokenReply.plain("First.\n---\nSecond."), "First. Second.")
    }

    func testEmojiAreDropped() {
        XCTAssertEqual(SpokenReply.plain("Done ✅ and shipped 🚀🔥."), "Done and shipped.")
        XCTAssertEqual(SpokenReply.plain("Good work 👍🏽"), "Good work.")
    }

    func testOnlyMarkupGivesNothingToSay() {
        XCTAssertEqual(SpokenReply.plain("***"), "")
        XCTAssertEqual(SpokenReply.plain("  \n \n"), "")
    }

    func testThousandsSeparatorsAreRemovedForSpeech() {
        XCTAssertEqual(SpokenReply.plain("About 1,200 steps left."), "About 1200 steps left.")
        XCTAssertEqual(SpokenReply.plain("Cost is $12,500 today."), "Cost is $12500 today.")
    }

    func testClockTimesAreLeftForTheVoiceEngine() {
        XCTAssertEqual(SpokenReply.plain("Leave by 4:15."), "Leave by 4:15.")
        XCTAssertEqual(SpokenReply.plain("Meet at 15:30 at the gate."), "Meet at 15:30 at the gate.")
    }

    func testPlainTwiceIsTheSameAsOnce() {
        let written = "## Plan\n- **Call** [Sam](tel:555)\n- Check https://example.com/x.\n\nThen rest 😀"
        let once = SpokenReply.plain(written)
        XCTAssertEqual(SpokenReply.plain(once), once)
    }

    // MARK: - A short first part

    func testAShortAnswerIsSpokenWhole() {
        let parts = SpokenReply.parts("The meeting moved to three. Sam confirmed.")
        XCTAssertEqual(parts, SpokenReply.Parts(now: "The meeting moved to three. Sam confirmed.", later: nil))
    }

    private func longAnswer(sentences: Int, wordsEach: Int = 10) -> String {
        (1...sentences).map { n in
            "Point \(n) " + Array(repeating: "word", count: wordsEach - 3).joined(separator: " ") + " end."
        }.joined(separator: " ")
    }

    func testALongAnswerPausesAtTheEndOfASentenceNearTheLimit() {
        let answer = longAnswer(sentences: 12)
        let parts = SpokenReply.parts(answer)
        XCTAssertEqual(SpokenReply.words(in: parts.now), 70)
        XCTAssertTrue(parts.now.hasSuffix("end."))
        XCTAssertEqual(parts.later.map(SpokenReply.words(in:)), 50)
        XCTAssertEqual(parts.now + " " + (parts.later ?? ""), answer)
    }

    func testAnAnswerOnlyALittleOverTheLimitIsNotCut() {
        let answer = longAnswer(sentences: 8)
        XCTAssertEqual(SpokenReply.words(in: answer), 80)
        XCTAssertNil(SpokenReply.parts(answer).later)
    }

    func testASentenceIsNeverCut() {
        let one = Array(repeating: "word", count: 200).joined(separator: " ") + "."
        XCTAssertEqual(SpokenReply.parts(one), SpokenReply.Parts(now: one, later: nil))
        let two = one + " And then a second one."
        let parts = SpokenReply.parts(two)
        XCTAssertEqual(parts.now, one)
        XCTAssertEqual(parts.later, "And then a second one.")
    }

    func testTheRestCanBeSplitAgain() {
        let answer = longAnswer(sentences: 30)
        var spoken: [String] = []
        var rest: String? = answer
        while let text = rest {
            let parts = SpokenReply.parts(text)
            spoken.append(parts.now)
            rest = parts.later
        }
        XCTAssertGreaterThan(spoken.count, 2)
        XCTAssertEqual(spoken.joined(separator: " "), answer)
    }

    // MARK: - A whole turn

    func testAShortReplyIsOnlyPutInPlainWords() {
        let turn = SpokenReply.turn([(text: "**Done.** Filed it.", from: "Indy")], short: true)
        XCTAssertEqual(turn, SpokenReply.Turn(lines: [.init(index: 0, text: "Done. Filed it.")], later: nil))
    }

    func testALongReplyPausesWithTheCueAndHoldsTheRest() {
        let answer = longAnswer(sentences: 12)
        let turn = SpokenReply.turn([(text: answer, from: "Indy")], short: true)
        XCTAssertEqual(turn.lines.count, 1)
        XCTAssertTrue(turn.lines[0].text.hasSuffix("end. " + SpokenReply.moreCue))
        XCTAssertEqual(turn.later.map(SpokenReply.words(in:)), 50)
    }

    func testWithShortRepliesOffNothingIsHeld() {
        let answer = longAnswer(sentences: 12)
        let turn = SpokenReply.turn([(text: answer, from: "Indy")], short: false)
        XCTAssertEqual(turn, SpokenReply.Turn(lines: [.init(index: 0, text: answer)], later: nil))
    }

    func testSeveralAssistantsShareTheTimeAndTheCueIsSaidOnce() {
        let turn = SpokenReply.turn([
            (text: longAnswer(sentences: 10), from: "Indy"),
            (text: "", from: "Rally"),
            (text: longAnswer(sentences: 10), from: "Driver"),
        ], short: true)
        XCTAssertEqual(turn.lines.map(\.index), [0, 2], "The empty reply is skipped and the others keep their places")
        XCTAssertEqual(SpokenReply.words(in: turn.lines[0].text), 30)
        XCTAssertFalse(turn.lines[0].text.contains(SpokenReply.moreCue))
        XCTAssertTrue(turn.lines[1].text.hasSuffix(SpokenReply.moreCue))
        let later = try? XCTUnwrap(turn.later)
        XCTAssertEqual(later?.hasPrefix("Indy went on: Point 4"), true)
        XCTAssertEqual(later?.contains("Driver went on: Point 4"), true)
    }

    func testOneLongReplyAmongShortOnesHoldsOnlyItsOwnRest() {
        let turn = SpokenReply.turn([
            (text: "All clear.", from: "Indy"),
            (text: longAnswer(sentences: 10), from: "Driver"),
        ], short: true)
        XCTAssertEqual(turn.lines[0].text, "All clear.")
        XCTAssertEqual(turn.later?.hasPrefix("Driver went on:"), true)
    }

    func testNothingToSayGivesNoLines() {
        XCTAssertEqual(SpokenReply.turn([(text: " ", from: "Indy")], short: true), SpokenReply.Turn(lines: [], later: nil))
        XCTAssertEqual(SpokenReply.turn([], short: true), SpokenReply.Turn(lines: [], later: nil))
    }

    func testGoOnWalksToTheEndAndSaysTheCueOnlyWhileThereIsMore() {
        let answer = longAnswer(sentences: 30)
        var held = SpokenReply.turn([(text: answer, from: "Indy")], short: true).later
        var steps = 0
        while let text = held {
            let next = SpokenReply.next(of: text)
            XCTAssertEqual(next.now.hasSuffix(SpokenReply.moreCue), next.later != nil)
            held = next.later
            steps += 1
        }
        XCTAssertEqual(steps, 4)
    }

    func testSentencesDoNotSplitNumbersOrLowercaseContinuations() {
        XCTAssertEqual(SpokenReply.sentences("It's 3.5 miles. Leave now!"), ["It's 3.5 miles.", "Leave now!"])
        XCTAssertEqual(SpokenReply.sentences("Use e.g. the red one."), ["Use e.g. the red one."])
        XCTAssertEqual(SpokenReply.sentences("He said \"go.\" Then left."), ["He said \"go.\"", "Then left."])
        XCTAssertEqual(SpokenReply.sentences("No stop at the end"), ["No stop at the end"])
        XCTAssertEqual(SpokenReply.sentences(""), [])
    }

    func testAskingForTheRest() {
        for said in ["Go on", "go on.", "Keep going!", "continue", "Read the rest", "What's the rest?", "what’s the rest"] {
            XCTAssertTrue(SpokenReply.asksForMore(said), said)
        }
        for said in ["go on a walk", "continue the timer", "tell me more about valves", "on", ""] {
            XCTAssertFalse(SpokenReply.asksForMore(said), said)
        }
    }

    func testTheCueIsShortAndSaysWhatToSay() {
        XCTAssertLessThanOrEqual(SpokenReply.words(in: SpokenReply.moreCue), 6)
        XCTAssertTrue(SpokenReply.asksForMore("go on"))
        XCTAssertTrue(SpokenReply.moreCue.lowercased().contains("go on"))
    }

    // MARK: - Acknowledgement

    private let bots = AssistantRoster.seed

    func testANamedAssistantIsNamedBack() {
        XCTAssertEqual(Acknowledgement.line(targetBot: "Indy", bots: bots, photo: false, turn: 0), "Asking Indy.")
        XCTAssertEqual(Acknowledgement.line(targetBot: "indy", bots: bots, photo: true, turn: 0), "Asking Indy.")
    }

    func testEveryoneIsEveryone() {
        XCTAssertEqual(Acknowledgement.line(targetBot: AssistantBot.allBots, bots: bots, photo: false, turn: 0), "Asking everyone.")
    }

    func testTheDefaultAssistantIsNotNamedBecauseItIsWhoJarvisAlwaysAsks() {
        let fallback = AssistantRoster.defaultBot(in: bots).name
        XCTAssertEqual(Acknowledgement.line(targetBot: fallback, bots: bots, photo: false, turn: 0), "On it.")
        XCTAssertEqual(Acknowledgement.line(targetBot: nil, bots: bots, photo: false, turn: 0), "On it.")
        XCTAssertEqual(Acknowledgement.line(targetBot: " ", bots: bots, photo: false, turn: 0), "On it.")
    }

    func testAnAssistantTheRosterDoesNotKnowIsStillNamed() {
        XCTAssertEqual(Acknowledgement.line(targetBot: "Scout", bots: bots, photo: false, turn: 0), "Asking Scout.")
    }

    func testAPhotoIsAcknowledgedAsLooking() {
        XCTAssertEqual(Acknowledgement.line(targetBot: nil, bots: bots, photo: true, turn: 3), "Taking a look.")
    }

    func testThePlainWordVariesAndNeverRepeatsBackToBack() {
        let lines = (0..<9).map { Acknowledgement.line(targetBot: nil, bots: bots, photo: false, turn: $0) }
        for (one, next) in zip(lines, lines.dropFirst()) {
            XCTAssertNotEqual(one, next)
        }
        XCTAssertEqual(Set(lines), Set(Acknowledgement.plain))
        XCTAssertEqual(Acknowledgement.line(targetBot: nil, bots: bots, photo: false, turn: -1), "Right away.")
    }

    func testGenericAcknowledgementsBecomeEarcons() {
        XCTAssertEqual(
            Acknowledgement.cue(targetBot: nil, bots: bots, photo: false, turn: 0),
            .earcon
        )
        let fallback = AssistantRoster.defaultBot(in: bots).name
        XCTAssertEqual(
            Acknowledgement.cue(targetBot: fallback, bots: bots, photo: false, turn: 1),
            .earcon
        )
    }

    func testNamedAndLookAcknowledgementsStaySpoken() {
        XCTAssertEqual(
            Acknowledgement.cue(targetBot: "Indy", bots: bots, photo: false, turn: 0),
            .speak("Asking Indy.")
        )
        XCTAssertEqual(
            Acknowledgement.cue(targetBot: nil, bots: bots, photo: true, turn: 0),
            .speak("Taking a look.")
        )
    }

    func testEveryAcknowledgementIsThreeWordsOrFewer() {
        var lines = Acknowledgement.plain
        lines.append(Acknowledgement.line(targetBot: "Indy", bots: bots, photo: false, turn: 0))
        lines.append(Acknowledgement.line(targetBot: AssistantBot.allBots, bots: bots, photo: false, turn: 0))
        lines.append(Acknowledgement.line(targetBot: nil, bots: bots, photo: true, turn: 0))
        for line in lines {
            XCTAssertLessThanOrEqual(SpokenReply.words(in: line), 3, line)
        }
    }
}
