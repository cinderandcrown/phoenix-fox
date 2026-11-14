// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

/// What one frame shows: names, badges, markers, and how sure a look is.
final class LookToTalkReadingTests: XCTestCase {
    private let roster = ["Fire Fox", "Indy", "Driver", "Rally"].map { LookName(bot: $0) }

    private func line(
        _ text: String, x: Double = 0.5, y: Double = 0.5, height: Double = 0.04, confidence: Double = 1
    ) -> TextFragment {
        TextFragment(text, box: FrameBox(x: x - 0.15, y: y - height / 2, width: 0.3, height: height), confidence: confidence)
    }

    private func code(_ payload: String, x: Double = 0.5, y: Double = 0.5) -> CodeSighting {
        CodeSighting(payload: payload, box: FrameBox(x: x - 0.05, y: y - 0.05, width: 0.1, height: 0.1))
    }

    private func read(_ text: [TextFragment], codes: [CodeSighting] = []) -> LookReading {
        WindowReader.read(ScreenView(text: text, codes: codes), roster: roster)
    }

    private func indy() -> LookTarget { .assistant("Indy") }

    // MARK: - Names

    func testANameAloneOnALineIsATitle() {
        let reading = read([line("Indy")])
        XCTAssertEqual(reading.candidates.count, 1)
        XCTAssertEqual(reading.candidates.first?.target, indy())
        XCTAssertEqual(reading.candidates.first?.evidence, .title)
        XCTAssertEqual(reading.candidates.first?.score ?? 0, 1, accuracy: 0.0001)
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: false))
    }

    func testAShortLineWithTheNameIsStillATitle() {
        let reading = read([line("Indy - Grok")])
        XCTAssertEqual(reading.candidates.first?.evidence, .title)
        XCTAssertEqual(reading.candidates.first?.score ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: false))
    }

    func testANameInAMiddlingLineIsAskedAbout() {
        let reading = read([line("pass this to Indy now please")])
        XCTAssertEqual(reading.candidates.first?.evidence, .mention)
        XCTAssertEqual(reading.candidates.first?.score ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(reading.verdict(), .unsure(indy(), other: nil))
    }

    func testANameInASentenceChoosesNobody() {
        // Read in Driver's window, this must not move the target to Indy.
        let reading = read([line("Sure, I will pass this over to Indy for you right now")])
        XCTAssertEqual(reading.candidates.first?.evidence, .mention)
        XCTAssertLessThan(reading.candidates.first?.score ?? 1, LookReading.askScore)
        XCTAssertEqual(reading.verdict(), .nothing)
    }

    func testTheWindowInFrontBeatsWhatItsTextMentions() {
        let reading = read([
            line("Driver", y: 0.2, height: 0.05),
            line("Sure, I will pass this over to Indy for you right now", y: 0.5, height: 0.03),
        ])
        XCTAssertEqual(reading.verdict(), .sure(.assistant("Driver"), deliberate: false))
    }

    func testTextWithNoNameFindsNothing() {
        XCTAssertEqual(read([line("Quarterly report"), line("Inbox (4)")]), .empty)
        XCTAssertEqual(read([]).verdict(), .nothing)
        XCTAssertEqual(WindowReader.read(ScreenView(text: [line("Indy")]), roster: []), .empty)
    }

    func testANameOfTwoWordsMustBeWholeAndInOrder() {
        XCTAssertEqual(read([line("Fire Fox")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: false))
        XCTAssertEqual(read([line("Fox Fire")]), .empty)
        XCTAssertEqual(read([line("Fire")]), .empty)
        XCTAssertEqual(read([line("Fire and Fox")]), .empty)
    }

    func testTheBrowserIsNotTheAssistant() {
        // The browser writes its name as one word. The assistant's is two.
        XCTAssertEqual(read([line("Firefox")]), .empty)
        XCTAssertEqual(read([line("Mozilla Firefox")]), .empty)
        XCTAssertEqual(read([line("FIREFOX")]), .empty)
        // A chat app that drops the space keeps the capital, and that is still two words.
        XCTAssertEqual(read([line("FireFox")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: false))
        XCTAssertEqual(read([line("fire_fox")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: false))
    }

    func testCapitalsDoNotMatter() {
        XCTAssertEqual(read([line("INDY")]).verdict(), .sure(indy(), deliberate: false))
        XCTAssertEqual(read([line("indy")]).verdict(), .sure(indy(), deliberate: false))
    }

    func testLettersTheRecognizerConfusesAreTheSame() {
        // A small L for a capital I, a one for either, a zero for an O.
        XCTAssertEqual(read([line("lndy")]).verdict(), .sure(indy(), deliberate: false))
        XCTAssertEqual(read([line("1ndy")]).verdict(), .sure(indy(), deliberate: false))
        XCTAssertEqual(read([line("Ral1y")]).verdict(), .sure(.assistant("Rally"), deliberate: false))
        XCTAssertEqual(read([line("DR1VER")]).verdict(), .sure(.assistant("Driver"), deliberate: false))
        XCTAssertEqual(read([line("Fire F0x")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: false))
    }

    func testWordsAreSplitAndFoldedTheSameWayEverywhere() {
        XCTAssertEqual(WindowReader.words("FireFox"), ["fire", "fox"])
        XCTAssertEqual(WindowReader.words("Firefox"), ["firefox"])
        XCTAssertEqual(WindowReader.words("TALK TO INDY"), ["taik", "to", "indy"])
        XCTAssertEqual(WindowReader.words("Indy — Grok (2)"), ["indy", "grok", "2"])
        XCTAssertEqual(WindowReader.words("  "), [])
        XCTAssertEqual(WindowReader.words("lndy"), WindowReader.words("Indy"))
    }

    func testOtherNamesTheWearerGaveCount() {
        let names = [LookName(bot: "Indy", others: ["indy_bot", "Indiana"]), LookName(bot: "Driver")]
        let handle = WindowReader.read(ScreenView(text: [line("indy_bot")]), roster: names)
        XCTAssertEqual(handle.verdict(), .sure(indy(), deliberate: false))
        let other = WindowReader.read(ScreenView(text: [line("Indiana")]), roster: names)
        XCTAssertEqual(other.verdict(), .sure(indy(), deliberate: false))
        XCTAssertEqual(LookName(bot: "Indy", others: ["Indiana"]).all, ["Indy", "Indiana"])
    }

    // MARK: - How sure the recognizer was, and how big the text is

    func testTextTheRecognizerDoubtsCountsForLess() {
        let doubted = read([line("Indy", confidence: 0.5)])
        XCTAssertEqual(doubted.candidates.first?.score ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(read([line("Indy", confidence: 0.2)]), .empty)
    }

    func testSmallPrintIsNotATitle() {
        let reading = read([
            line("Quarterly report", y: 0.2, height: 0.05),
            line("Notes for the week", y: 0.3, height: 0.05),
            line("Indy", y: 0.5, height: 0.02),
        ])
        XCTAssertEqual(reading.candidates.first?.score ?? 0, 0.8, accuracy: 0.0001)
    }

    func testANameSeenMoreThanOnceIsSurer() {
        let once = read([line("Indy - Grok", y: 0.5)])
        let twice = read([line("Indy - Grok", y: 0.5), line("Indy", y: 0.6), line("Indy", y: 0.7), line("Indy", y: 0.8)])
        let single = once.candidates.first?.score ?? 0
        let many = twice.candidates.first?.score ?? 0
        XCTAssertEqual(twice.candidates.count, 1, "One entry for each assistant")
        XCTAssertGreaterThan(many, single)
        XCTAssertLessThanOrEqual(many, 1)
    }

    // MARK: - Where it is

    func testFacingIsMostlyAboutLeftAndRight() {
        func box(_ x: Double, _ y: Double) -> FrameBox { FrameBox(x: x, y: y, width: 0, height: 0) }
        XCTAssertEqual(WindowReader.facing(box(0.5, 0.5)), 1, accuracy: 0.0001)
        XCTAssertEqual(WindowReader.facing(box(0, 0)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(WindowReader.facing(box(1, 1)), 0.5, accuracy: 0.0001)
        // A title at the top of a window dead ahead loses little.
        XCTAssertEqual(WindowReader.facing(box(0.5, 0)), 0.9, accuracy: 0.0001)
        XCTAssertEqual(WindowReader.facing(box(0, 0.5)), 0.6, accuracy: 0.0001)
        XCTAssertEqual(WindowReader.facing(box(-3, 9)), 0.5, accuracy: 0.0001)
    }

    func testTheWindowTheWearerFacesWins() {
        let reading = read([line("Indy", x: 0.5), line("Driver", x: 0.9)])
        XCTAssertEqual(reading.candidates.map(\.target.name), ["Indy", "Driver"])
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: false))
    }

    func testLookingBetweenTwoWindowsIsAskedAbout() {
        let reading = read([line("Indy", x: 0.36), line("Driver", x: 0.66)])
        XCTAssertEqual(reading.verdict(), .unsure(indy(), other: .assistant("Driver")))
    }

    // MARK: - Badges

    func testABadgeIsFoundInOneLook() {
        let reading = read([line("TALK TO INDY")])
        XCTAssertEqual(reading.candidates.first?.evidence, .badge)
        XCTAssertEqual(reading.candidates.first?.isDeliberate, true)
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: true))
        XCTAssertEqual(read([line("Look to Talk: Fire Fox")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: true))
    }

    func testABadgeDoesNotNeedGoodLightOrACentralPlace() {
        // The recognizer's doubt and the edge of the frame do not stop a badge.
        let reading = read([line("TALK TO INDY", x: 0.15, y: 0.9, confidence: 0.4)])
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: true))
    }

    func testABadgeMayWrapOntoTwoLines() {
        let wrapped = read([line("TALK TO", y: 0.40, height: 0.06), line("INDY", y: 0.48, height: 0.06)])
        XCTAssertEqual(wrapped.candidates.first?.evidence, .badge)
        XCTAssertEqual(wrapped.verdict(), .sure(indy(), deliberate: true))

        // The words must be directly over the name: not far above, not beside, not under.
        let far = read([line("TALK TO", y: 0.1, height: 0.06), line("INDY", y: 0.48, height: 0.06)])
        XCTAssertEqual(far.candidates.first?.evidence, .title)
        let beside = read([line("TALK TO", x: 0.15, y: 0.40, height: 0.06), line("INDY", x: 0.85, y: 0.48, height: 0.06)])
        XCTAssertEqual(beside.candidates.first?.evidence, .title)
        let under = read([line("INDY", y: 0.40, height: 0.06), line("TALK TO", y: 0.48, height: 0.06)])
        XCTAssertEqual(under.candidates.first?.evidence, .title)
        // And only a name alone on its line is completed this way.
        let title = read([line("TALK TO", y: 0.40, height: 0.06), line("Indy - Grok", y: 0.48, height: 0.06)])
        XCTAssertEqual(title.candidates.first?.evidence, .title)
    }

    func testABadgeHasNothingElseOnItsLine() {
        let reading = read([line("you can talk to Indy about that")])
        XCTAssertEqual(reading.candidates.first?.evidence, .mention)
        XCTAssertNotEqual(reading.verdict(), .sure(indy(), deliberate: true))
    }

    func testTwoBadgesSideBySideAreAskedAbout() {
        let reading = read([line("TALK TO INDY", x: 0.42), line("TALK TO DRIVER", x: 0.6)])
        XCTAssertEqual(reading.verdict(), .unsure(indy(), other: .assistant("Driver")))
        let faced = read([line("TALK TO INDY", x: 0.5), line("TALK TO DRIVER", x: 0.95)])
        XCTAssertEqual(faced.verdict(), .sure(indy(), deliberate: true))
    }

    func testABadgeOffToTheSideDoesNotBeatTheWindowAhead() {
        let reading = read([line("Driver", x: 0.5), line("TALK TO INDY", x: 0.8)])
        XCTAssertEqual(reading.candidates.first?.target.name, "Driver")
        XCTAssertEqual(reading.verdict(), .sure(.assistant("Driver"), deliberate: false))
    }

    // MARK: - Markers

    func testAMarkerNamesItsAssistant() {
        let reading = read([], codes: [code("PFX:BOT:INDY")])
        XCTAssertEqual(reading.candidates.first?.evidence, .marker)
        XCTAssertEqual(reading.verdict(), .sure(indy(), deliberate: true))
        XCTAssertEqual(read([], codes: [code(" pfx:bot:fire fox\n")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: true))
        XCTAssertEqual(read([], codes: [code("PFX:BOT:FIRE-FOX")]).verdict(), .sure(.assistant("Fire Fox"), deliberate: true))
    }

    func testOtherCodesAreIgnored() {
        XCTAssertEqual(read([], codes: [code("https://example.com/indy")]), .empty)
        XCTAssertEqual(read([], codes: [code("PFX:BOT:")]), .empty)
        XCTAssertEqual(read([], codes: [code("PFX:BOT:NOBODY")]), .empty)
        XCTAssertEqual(read([], codes: [code("INDY")]), .empty)
        XCTAssertEqual(read([], codes: [code("PFX:DOC:INDY")]), .empty)
    }

    func testAMarkerIsWrittenInCapitalsWithoutAccents() {
        XCTAssertEqual(LookMarker.payload(for: "Indy"), "PFX:BOT:INDY")
        XCTAssertEqual(LookMarker.payload(for: "Fire Fox"), "PFX:BOT:FIRE FOX")
        XCTAssertEqual(LookMarker.payload(for: "  Zoë   Bot "), "PFX:BOT:ZOE BOT")
        XCTAssertEqual(LookMarker.payload(for: "R2-D2"), "PFX:BOT:R2 D2")
        XCTAssertNil(LookMarker.payload(for: "🦊"))
        XCTAssertNil(LookMarker.payload(for: ""))
    }

    func testAMarkerMadeForANameIsReadBackAsThatName() {
        for entry in roster + [LookName(bot: "Zoë"), LookName(bot: "R2-D2")] {
            guard let payload = LookMarker.payload(for: entry.bot) else { return XCTFail("No marker for \(entry.bot)") }
            XCTAssertTrue(LookMarker.names(payload, entry), entry.bot)
            // Every character must be in the compact alphabet of a QR code.
            XCTAssertTrue(payload.allSatisfy { "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".contains($0) }, payload)
        }
        XCTAssertTrue(LookMarker.names("PFX:BOT:INDIANA", LookName(bot: "Indy", others: ["Indiana"])))
        XCTAssertFalse(LookMarker.names("PFX:BOT:INDY", LookName(bot: "Driver")))
    }

    // MARK: - The verdict

    private func candidate(_ name: String, _ score: Double, _ evidence: LookCandidate.Evidence = .title) -> LookCandidate {
        LookCandidate(target: .assistant(name), score: score, evidence: evidence, box: FrameBox(x: 0, y: 0, width: 0, height: 0))
    }

    func testAReadingIsKeptBestFirst() {
        let reading = LookReading(candidates: [candidate("Driver", 0.5), candidate("Indy", 0.9), candidate("Rally", 0.7)])
        XCTAssertEqual(reading.candidates.map(\.target.name), ["Indy", "Rally", "Driver"])
        XCTAssertEqual(reading.score(of: .assistant("Rally")), 0.7)
        XCTAssertEqual(reading.score(of: .assistant("Fire Fox")), 0)
    }

    func testTheVerdictNeedsAClearLead() {
        XCTAssertEqual(LookReading(candidates: [candidate("Indy", 0.72)]).verdict(), .sure(indy(), deliberate: false))
        XCTAssertEqual(LookReading(candidates: [candidate("Indy", 0.71)]).verdict(), .unsure(indy(), other: nil))
        XCTAssertEqual(LookReading(candidates: [candidate("Indy", 0.42)]).verdict(), .unsure(indy(), other: nil))
        XCTAssertEqual(LookReading(candidates: [candidate("Indy", 0.41)]).verdict(), .nothing)
        XCTAssertEqual(
            LookReading(candidates: [candidate("Indy", 0.9), candidate("Driver", 0.8)]).verdict(),
            .unsure(indy(), other: .assistant("Driver"))
        )
        XCTAssertEqual(
            LookReading(candidates: [candidate("Indy", 0.9), candidate("Driver", 0.7)]).verdict(),
            .sure(indy(), deliberate: false)
        )
        // Something too faint to count does not spoil a clear lead.
        XCTAssertEqual(
            LookReading(candidates: [candidate("Indy", 0.9), candidate("Driver", 0.3)]).verdict(),
            .sure(indy(), deliberate: false)
        )
    }

    func testATargetTheWearerRefusedIsLeftOut() {
        let reading = LookReading(candidates: [candidate("Indy", 0.9), candidate("Driver", 0.8)])
        XCTAssertEqual(reading.verdict { $0.name != "Indy" }, .sure(.assistant("Driver"), deliberate: false))
        XCTAssertEqual(reading.verdict { _ in false }, .nothing)
    }

    func testAHeldTargetOnlyHasToBePlausible() {
        let reading = LookReading(candidates: [candidate("Indy", 0.45, .mention)])
        XCTAssertTrue(reading.stillShows(indy()))
        XCTAssertFalse(reading.stillShows(.assistant("Driver")))
        XCTAssertFalse(LookReading(candidates: [candidate("Indy", 0.3)]).stillShows(indy()))
    }

    func testTargetsOfDifferentKindsAreDifferentTargets() {
        XCTAssertEqual(LookTarget.assistant("Indy"), LookTarget(kind: .assistant, name: "Indy"))
        XCTAssertNotEqual(LookTarget.assistant("Indy"), LookTarget.assistant("indy"))
        XCTAssertEqual(LookTarget.Kind.assistant.rawValue, "assistant")
    }

    // MARK: - Tones

    private func pitches(_ tone: LookTracker.Tone, place: Int? = 0) -> [Double] {
        LookTone.segments(tone, place: place).filter { $0.startHertz > 0 }.map(\.startHertz)
    }

    func testEachToneHasItsOwnShape() {
        let found = pitches(.found)
        XCTAssertEqual(found.count, 2)
        XCTAssertLessThan(found[0], found[1], "Found rises")

        let locked = pitches(.locked)
        XCTAssertEqual(locked.count, 3)
        XCTAssertEqual(locked, locked.sorted(), "Locked rises")
        XCTAssertEqual(locked[2], locked[0] * 2, accuracy: 0.001, "and ends an octave up")

        let released = pitches(.released)
        XCTAssertEqual(released.count, 2)
        XCTAssertGreaterThan(released[0], released[1], "Let go falls")

        let unsure = LookTone.segments(.unsure, place: 0)
        XCTAssertNotEqual(unsure.last?.startHertz, unsure.last?.endHertz, "Not sure ends on a slide")
        XCTAssertLessThan(unsure.last?.startHertz ?? 0, unsure.last?.endHertz ?? 0)

        let shapes = LookTracker.Tone.allCases.map { LookTone.segments($0, place: 0) }
        for (index, shape) in shapes.enumerated() {
            for other in shapes.dropFirst(index + 1) { XCTAssertNotEqual(shape, other) }
        }
    }

    func testTonesAreShort() {
        for tone in LookTracker.Tone.allCases {
            let segments = LookTone.segments(tone, place: 3)
            let length = segments.reduce(0) { $0 + $1.seconds }
            XCTAssertGreaterThan(length, 0.15, tone.rawValue)
            XCTAssertLessThan(length, 0.5, tone.rawValue)
            XCTAssertTrue(segments.allSatisfy { $0.seconds > 0 })
        }
    }

    func testEachAssistantHasItsOwnNote() {
        let starts = (0..<LookTone.roots.count).map { pitches(.locked, place: $0)[0] }
        XCTAssertEqual(Set(starts).count, LookTone.roots.count)
        XCTAssertEqual(starts, starts.sorted())
        // A sixth assistant shares the first one's note, and a tone about nobody uses it too.
        XCTAssertEqual(pitches(.locked, place: LookTone.roots.count), pitches(.locked, place: 0))
        XCTAssertEqual(pitches(.released, place: nil), pitches(.released, place: 0))
        XCTAssertEqual(pitches(.found, place: -4), pitches(.found, place: 0))
    }

    func testAToneIsASoundFile() {
        for tone in LookTracker.Tone.allCases {
            let wav = LookTone.wav(tone, place: 1)
            XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertGreaterThan(wav.count, 4_000)
        }
    }
}
