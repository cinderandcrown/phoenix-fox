// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class SoundAlertPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10_000)

    func testOneLoudWindowIsNotAnAlert() {
        var policy = SoundAlertPolicy()
        XCTAssertTrue(policy.observe([("door_bell", 0.9)], at: start).isEmpty)
        XCTAssertTrue(policy.observe([("speech", 0.9)], at: start.addingTimeInterval(1)).isEmpty)
        // The streak was broken, so the next single window does not fire either.
        XCTAssertTrue(policy.observe([("door_bell", 0.9)], at: start.addingTimeInterval(2)).isEmpty)
    }

    func testTwoWindowsInARowFireOnceThenWait() {
        var policy = SoundAlertPolicy()
        _ = policy.observe([("siren", 0.7)], at: start)
        let alerts = policy.observe([("ambulance_siren", 0.8)], at: start.addingTimeInterval(1))
        XCTAssertEqual(alerts.map(\.kind), [.siren])
        // The siren keeps going: no second alert until the wait is over.
        for second in 2..<12 {
            XCTAssertTrue(policy.observe([("siren", 0.9)], at: start.addingTimeInterval(Double(second))).isEmpty)
        }
        XCTAssertEqual(policy.observe([("siren", 0.9)], at: start.addingTimeInterval(14)).map(\.kind), [.siren])
    }

    func testUrgentSoundsUseALowerThreshold() {
        var policy = SoundAlertPolicy()
        _ = policy.observe([("smoke_detector", 0.55), ("door_bell", 0.55)], at: start)
        let alerts = policy.observe([("smoke_detector", 0.55), ("door_bell", 0.55)], at: start.addingTimeInterval(1))
        XCTAssertEqual(alerts.map(\.kind), [.smokeAlarm])
    }

    func testDisabledKindsAndUnknownLabelsAreIgnored() {
        var policy = SoundAlertPolicy(enabled: [.doorbell])
        _ = policy.observe([("dog_bark", 0.99), ("music", 0.99)], at: start)
        XCTAssertTrue(policy.observe([("dog_bark", 0.99), ("music", 0.99)], at: start.addingTimeInterval(1)).isEmpty)
    }

    func testUrgentAlertsComeFirst() {
        var policy = SoundAlertPolicy()
        let scores: [(label: String, confidence: Double)] = [("door_bell", 0.95), ("glass_breaking", 0.6)]
        _ = policy.observe(scores, at: start)
        XCTAssertEqual(policy.observe(scores, at: start.addingTimeInterval(1)).map(\.kind), [.glassBreaking, .doorbell])
    }

    func testLabelsAreMatchedByTheirWords() {
        XCTAssertEqual(SoundKind.matching("police_siren"), .siren)
        XCTAssertEqual(SoundKind.matching("civil_defense_siren"), .siren)
        XCTAssertEqual(SoundKind.matching("baby_crying"), .babyCrying)
        XCTAssertEqual(SoundKind.matching("knock"), .knock)
        XCTAssertNil(SoundKind.matching("acoustic_guitar"))
        XCTAssertEqual(SoundKind.supported(byLabels: ["siren", "speech", "dog_bark"]), [.siren, .dogBark])
    }
}

final class NameCallDetectorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 20_000)

    func testTheNameIsHeardOncePerTimeItIsSaid() {
        var detector = NameCallDetector(names: ["Brandon", "Bran"])
        XCTAssertNil(detector.heard("hey", at: start))
        XCTAssertEqual(detector.heard("hey Brandon", at: start.addingTimeInterval(0.3)), "brandon")
        // The same line growing must not fire again.
        XCTAssertNil(detector.heard("hey Brandon are you coming", at: start.addingTimeInterval(0.6)))
    }

    func testANameInsideAnotherWordDoesNotCount() {
        var detector = NameCallDetector(names: ["Al"])
        XCTAssertNil(detector.heard("that is also fine", at: start))
    }

    func testRepeatsWithinTenSecondsAreOneCall() {
        var detector = NameCallDetector(names: ["Sam"])
        XCTAssertEqual(detector.heard("Sam", at: start), "sam")
        XCTAssertNil(detector.heard("Sam Sam", at: start.addingTimeInterval(2)))
        XCTAssertEqual(detector.heard("Sam Sam over here Sam", at: start.addingTimeInterval(15)), "sam")
    }

    func testANewLineStartsFresh() {
        var detector = NameCallDetector(names: ["Mary Ann"])
        XCTAssertNil(detector.heard("is that Mary", at: start))
        XCTAssertEqual(detector.heard("is that Mary Ann", at: start.addingTimeInterval(0.2)), "mary ann")
        XCTAssertNil(detector.heard("yes", at: start.addingTimeInterval(20)))
        XCTAssertEqual(detector.heard("yes Mary Ann", at: start.addingTimeInterval(21)), "mary ann")
    }
}

final class CaptionBookTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 30_000)

    func testAPauseClosesTheLineAndTheSessionTextIsNotRepeated() {
        var book = CaptionBook()
        book.update("good morning", at: start)
        book.update("good morning everyone", at: start.addingTimeInterval(0.5))
        XCTAssertEqual(book.live, "good morning everyone")
        book.tick(at: start.addingTimeInterval(1.0))
        XCTAssertTrue(book.lines.isEmpty, "0.5 s is not a pause")
        book.tick(at: start.addingTimeInterval(2.0))
        XCTAssertEqual(book.lines.map(\.text), ["good morning everyone"])
        XCTAssertEqual(book.live, "")
        // The recognizer keeps the whole session; only the new words form the next line.
        book.update("good morning everyone how are you", at: start.addingTimeInterval(3))
        XCTAssertEqual(book.live, "how are you")
        XCTAssertEqual(book.lines[0].at, start)
    }

    func testALongLineIsClosedByLength() {
        var book = CaptionBook()
        book.maxCharacters = 20
        book.update("one two three four five", at: start)
        XCTAssertEqual(book.lines.map(\.text), ["one two three four five"])
        book.update("one two three four five six", at: start.addingTimeInterval(1))
        XCTAssertEqual(book.live, "six")
    }

    func testANewRecognizerSessionStartsFromNothing() {
        var book = CaptionBook()
        book.update("first session", at: start)
        book.sessionEnded(at: start.addingTimeInterval(1))
        book.update("second", at: start.addingTimeInterval(2))
        XCTAssertEqual(book.lines.map(\.text), ["first session"])
        XCTAssertEqual(book.live, "second")
    }

    func testARevisionShorterThanWhatWasClosedShowsNothingNew() {
        var book = CaptionBook()
        book.update("one two three", at: start)
        book.commit(at: start)
        book.update("one two", at: start.addingTimeInterval(1))
        XCTAssertEqual(book.live, "")
    }

    func testRecentAndTranscript() {
        var book = CaptionBook()
        book.update("old line", at: start)
        book.commit(at: start)
        book.update("old line new line", at: start.addingTimeInterval(100))
        book.commit(at: start.addingTimeInterval(100))
        book.update("old line new line still talking", at: start.addingTimeInterval(110))
        XCTAssertEqual(book.recent(seconds: 30, now: start.addingTimeInterval(115)), ["new line", "still talking"])
        let zone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(book.transcript(timeZone: zone), "[08:20:00] old line\n[08:21:40] new line")
    }

    func testClearingKeepsTheSessionWordsSkipped() {
        var book = CaptionBook()
        book.update("private words", at: start)
        book.clear()
        book.update("private words then more", at: start.addingTimeInterval(1))
        XCTAssertEqual(book.live, "then more")
        XCTAssertTrue(book.lines.isEmpty)
    }

    func testTailWrapsForASmallDisplay() {
        var book = CaptionBook()
        book.update("the quick brown fox jumps over the lazy dog", at: start)
        XCTAssertEqual(book.tail(lines: 2, charactersPerLine: 16), ["fox jumps over", "the lazy dog"])
    }

    func testHistoryIsBounded() {
        var book = CaptionBook()
        book.capacity = 3
        var text = ""
        for index in 0..<5 {
            text += " word\(index)"
            book.update(text, at: start.addingTimeInterval(Double(index)))
            book.commit(at: start.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(book.lines.map(\.text), ["word2", "word3", "word4"])
    }
}

final class GuideNarratorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 40_000)

    private func box(midX: Double, height: Double = 0.3) -> FrameBox {
        FrameBox(x: midX - 0.05, y: 0.5 - height / 2, width: 0.1, height: height)
    }

    func testTheMostPressingThingsAreSaidFirstAndOnlyTwo() {
        var narrator = GuideNarrator()
        let callouts = narrator.callouts(for: [
            Sighting(.sign, label: "Pharmacy"),
            Sighting(.person, box: box(midX: 0.1)),
            Sighting(.stairs),
            Sighting(.vehicle, box: box(midX: 0.9), label: "bus"),
        ], at: start)
        XCTAssertEqual(callouts.map(\.text), ["Bus, on your right.", "Stairs in view."])
        XCTAssertTrue(callouts.allSatisfy(\.urgent))
    }

    func testTheSameThingIsNotRepeatedUntilTimePasses() {
        var narrator = GuideNarrator()
        let seen = [Sighting(.person, box: box(midX: 0.5))]
        XCTAssertEqual(narrator.callouts(for: seen, at: start).map(\.text), ["Person, ahead."])
        XCTAssertTrue(narrator.callouts(for: seen, at: start.addingTimeInterval(3)).isEmpty)
        XCTAssertEqual(narrator.callouts(for: seen, at: start.addingTimeInterval(9)).count, 1)
    }

    func testSomethingComingCloseIsSaidAgainAtOnce() {
        var narrator = GuideNarrator()
        _ = narrator.callouts(for: [Sighting(.person, box: box(midX: 0.5))], at: start)
        let callouts = narrator.callouts(for: [Sighting(.person, box: box(midX: 0.5, height: 0.8))], at: start.addingTimeInterval(1))
        XCTAssertEqual(callouts, [Callout(text: "Person, close, ahead.", side: .ahead, urgent: true)])
    }

    func testPeopleOnTheSameSideAreCounted() {
        var narrator = GuideNarrator()
        let callouts = narrator.callouts(for: [
            Sighting(.person, box: box(midX: 0.05)), Sighting(.person, box: box(midX: 0.1)), Sighting(.person, box: box(midX: 0.15)),
        ], at: start)
        XCTAssertEqual(callouts.map(\.text), ["Three people, on your left."])
    }

    func testSidesCoverTheFrame() {
        XCTAssertEqual(Side(midX: 0.0), .left)
        XCTAssertEqual(Side(midX: 0.3), .slightlyLeft)
        XCTAssertEqual(Side(midX: 0.5), .ahead)
        XCTAssertEqual(Side(midX: 0.7), .slightlyRight)
        XCTAssertEqual(Side(midX: 1.0), .right)
    }

    func testFindingAnObject() {
        let sightings = [Sighting(.door, box: box(midX: 0.85)), Sighting(.sign, label: "EXIT"), Sighting(.stairs)]
        XCTAssertEqual(ObjectFinder.answer(for: "door", in: sightings), "The door is on your right.")
        XCTAssertEqual(ObjectFinder.answer(for: "exit", in: sightings), "A sign that says EXIT is in view, but I can't tell which side. Turn slowly and ask again.")
        XCTAssertNil(ObjectFinder.answer(for: "elevator", in: sightings))
    }
}

final class CueToneTests: XCTestCase {
    func testDirectionIsCarriedByPitchSoItSurvivesMono() {
        let left = CueTone.segments(side: .left, urgent: false)
        let right = CueTone.segments(side: .right, urgent: false)
        let ahead = CueTone.segments(side: .ahead, urgent: false)
        XCTAssertGreaterThan(left[0].startHertz, left[0].endHertz)
        XCTAssertLessThan(right[0].startHertz, right[0].endHertz)
        XCTAssertEqual(ahead[0].startHertz, ahead[0].endHertz)
        XCTAssertEqual(CueTone.segments(side: nil, urgent: true).count, 3)
    }

    func testSamplesStartAndEndSilentAndStayInRange() {
        let samples = CueTone.samples(CueTone.segments(side: .right, urgent: true))
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(samples.map(abs).max() ?? 1, 0.5)
        XCTAssertEqual(samples.count, Int(0.14 * 22_050) * 2 + Int(0.06 * 22_050))
    }

    func testWavHeader() {
        let data = CueTone.wav([0, 0.5, -0.5, 0])
        XCTAssertEqual(data.count, 44 + 8)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(data[40], 8, "data chunk length, low byte")
    }
}

final class WalkingRouteTests: XCTestCase {
    // A route north along one street, then east along another. One degree of latitude is
    // about 111 km, so 0.0009 degrees is about 100 m.
    private let origin = Coordinate(40.0000, -75.0000)
    private let corner = Coordinate(40.0009, -75.0000)
    private let end = Coordinate(40.0009, -74.9990)

    private var route: WalkingRoute {
        WalkingRoute(destination: "the library", steps: [
            .init(instruction: "Head north on Oak Street", path: [origin, corner]),
            .init(instruction: "Turn right onto Main Street", path: [corner, end]),
        ])
    }

    private func fix(_ latitude: Double, _ longitude: Double, accuracy: Double = 8, course: Double? = nil) -> LocationFix {
        LocationFix(coordinate: Coordinate(latitude, longitude), accuracy: accuracy, course: course)
    }

    func testGeometry() {
        XCTAssertEqual(origin.distance(to: corner), 100, accuracy: 1)
        XCTAssertEqual(origin.bearing(to: corner), 0, accuracy: 0.5)
        XCTAssertEqual(corner.bearing(to: end), 90, accuracy: 0.5)
        XCTAssertEqual(Coordinate(40.00045, -74.9995).distance(toPath: [origin, corner]), 42.6, accuracy: 1)
    }

    func testATurnIsAnnouncedBeforeItAndAtIt() {
        var progress = RouteProgress(route: route, metric: true)
        XCTAssertEqual(progress.begin(), "Walking to the library, 185 meters. Head north on Oak Street.")
        XCTAssertEqual(progress.update(fix(40.0003, -75.0)), [])
        XCTAssertEqual(progress.update(fix(40.0006, -75.0)), [.say("In 35 meters, turn right onto Main Street.")])
        XCTAssertEqual(progress.update(fix(40.0007, -75.0)), [], "said once, not on every fix")
        XCTAssertEqual(progress.update(fix(40.00085, -75.0)), [.say("Turn right onto Main Street now.")])
        XCTAssertEqual(progress.stepIndex, 1)
        XCTAssertEqual(progress.update(fix(40.0009, -74.9995)), [])
        XCTAssertEqual(progress.update(fix(40.0009, -74.99905)), [.arrived("You have arrived. The library should be within a few steps.")])
        XCTAssertTrue(progress.finished)
        XCTAssertEqual(progress.update(fix(40.0009, -74.9990)), [])
    }

    func testThreeFixesOffTheRouteAskForANewOne() {
        var progress = RouteProgress(route: route, metric: true)
        _ = progress.begin()
        let away = fix(40.0004, -75.0010)
        XCTAssertEqual(progress.update(away), [])
        XCTAssertEqual(progress.update(away), [])
        XCTAssertEqual(progress.update(away), [.offRoute])
    }

    func testOneStrayFixIsForgiven() {
        var progress = RouteProgress(route: route, metric: true)
        _ = progress.begin()
        _ = progress.update(fix(40.0004, -75.0010))
        _ = progress.update(fix(40.0004, -75.0010))
        XCTAssertEqual(progress.update(fix(40.0004, -75.0)), [])
        XCTAssertEqual(progress.update(fix(40.0004, -75.0010)), [])
    }

    func testAVagueFixIsIgnored() {
        var progress = RouteProgress(route: route, metric: true)
        _ = progress.begin()
        XCTAssertEqual(progress.update(fix(40.00085, -75.0, accuracy: 120)), [])
        XCTAssertEqual(progress.stepIndex, 0)
    }

    func testStatusGivesTheClockDirection() {
        var progress = RouteProgress(route: route, metric: false)
        _ = progress.begin()
        // Walking east, the corner to the north is at nine o'clock.
        let status = progress.status(at: fix(40.0006, -75.0, course: 90))
        XCTAssertEqual(status, "In 110 feet, turn right onto Main Street. It's at your 9 o'clock.")
        XCTAssertEqual(RouteProgress.clock(from: fix(40.0, -75.0, course: 0), to: corner), 12)
        XCTAssertNil(RouteProgress.clock(from: fix(40.0, -75.0), to: corner))
    }

    func testDistancesAreRoundedTheWayPeopleSayThem() {
        XCTAssertEqual(Distance.spoken(3, metric: true), "5 meters")
        XCTAssertEqual(Distance.spoken(47, metric: true), "45 meters")
        XCTAssertEqual(Distance.spoken(1500, metric: true), "1.5 kilometers")
        XCTAssertEqual(Distance.spoken(30, metric: false), "100 feet")
        XCTAssertEqual(Distance.spoken(804.672, metric: false), "0.5 miles")
    }
}
