// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class StreamPlanTests: XCTestCase {
    private var everything: GlassesCapabilitySettings {
        var glasses = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &glasses)
        return glasses
    }

    func testOneLookNeverCarriesSound() {
        XCTAssertNil(StreamPlanner.profile(for: .still, capabilities: everything, heat: .normal, soundWanted: true)?.sound)
    }

    func testAStandardBuildKeepsTheStreamItAlwaysHad() {
        for purpose in StreamPurpose.allCases {
            let profile = StreamPlanner.profile(for: purpose, capabilities: GlassesCapabilitySettings(), heat: .normal, soundWanted: true)
            XCTAssertEqual(profile, .baseline, "\(purpose)")
        }
        XCTAssertEqual(StreamProfile.baseline.resolution, .medium)
        XCTAssertEqual(StreamProfile.baseline.frameRate, 7)
        XCTAssertNil(StreamProfile.baseline.sound)
    }

    func testEveryPlanUsesAFrameRateTheGlassesAccept() {
        let heats: [GlassesHeat] = [.normal, .light, .moderate, .severe]
        for purpose in StreamPurpose.allCases {
            for heat in heats {
                for capabilities in [GlassesCapabilitySettings(), everything] {
                    guard let profile = StreamPlanner.profile(for: purpose, capabilities: capabilities, heat: heat, soundWanted: true) else {
                        return XCTFail("No plan for \(purpose) at \(heat)")
                    }
                    XCTAssertTrue(StreamPlanner.frameRates.contains(profile.frameRate), "\(purpose) at \(heat): \(profile.frameRate)")
                    XCTAssertLessThanOrEqual(profile.imagesPerSecond, Double(profile.frameRate))
                    XCTAssertGreaterThan(profile.imagesPerSecond, 0)
                }
            }
        }
    }

    func testARecordingGetsTheMostTheGlassesOffer() {
        let profile = StreamPlanner.profile(for: .recording, capabilities: everything, heat: .normal)
        XCTAssertEqual(profile?.resolution, .high)
        XCTAssertEqual(profile?.frameRate, 30)
        XCTAssertEqual(profile?.sound, .full)
        XCTAssertEqual(profile?.resolution.pixels.width, 720)
        XCTAssertEqual(profile?.resolution.pixels.height, 1280)
    }

    func testAStillTradesFrameRateForSharpness() {
        let profile = StreamPlanner.profile(for: .still, capabilities: everything, heat: .normal)
        XCTAssertEqual(profile?.resolution, .high)
        XCTAssertEqual(profile?.frameRate, 7)
        XCTAssertNil(profile?.sound)
    }

    func testGuideModeGetsFreshFrames() {
        let profile = StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal)
        XCTAssertEqual(profile?.frameRate, 24)
    }

    func testSoundComesOnlyWhenSomethingListensAndTheSwitchIsOn() {
        XCTAssertNil(StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal, soundWanted: false)?.sound)
        XCTAssertEqual(StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal, soundWanted: true)?.sound, .speech)

        var quiet = everything
        quiet.ambientAudio = false
        XCTAssertNil(StreamPlanner.profile(for: .guide, capabilities: quiet, heat: .normal, soundWanted: true)?.sound)
        XCTAssertNil(StreamPlanner.profile(for: .recording, capabilities: quiet, heat: .normal)?.sound)
    }

    func testHeatTakesThePlanDownAndThenRefuses() {
        let cool = StreamPlanner.profile(for: .recording, capabilities: everything, heat: .light)
        XCTAssertEqual(cool?.frameRate, 30)

        let warm = StreamPlanner.profile(for: .recording, capabilities: everything, heat: .moderate)
        XCTAssertEqual(warm?.frameRate, 15)
        XCTAssertEqual(warm?.resolution, .high)

        let hot = StreamPlanner.profile(for: .recording, capabilities: everything, heat: .severe)
        XCTAssertEqual(hot?.frameRate, 7)
        XCTAssertEqual(hot?.resolution, .medium)
        XCTAssertEqual(hot?.sound, .full, "A recording keeps its sound.")

        let hotGuide = StreamPlanner.profile(for: .guide, capabilities: everything, heat: .severe, soundWanted: true)
        XCTAssertNil(hotGuide?.sound)

        XCTAssertNil(StreamPlanner.profile(for: .still, capabilities: everything, heat: .critical))
        XCTAssertNil(StreamPlanner.profile(for: .still, capabilities: GlassesCapabilitySettings(), heat: .critical))
    }

    func testARunningStreamIsReusedOnlyWhenItIsGoodEnough() {
        let recording = StreamProfile(resolution: .high, frameRate: 30, sound: .full, imagesPerSecond: 15)
        let still = StreamProfile(resolution: .high, frameRate: 7, sound: nil, imagesPerSecond: 7)
        let listening = StreamProfile(resolution: .medium, frameRate: 7, sound: .speech, imagesPerSecond: 7)
        XCTAssertTrue(recording.covers(still))
        XCTAssertTrue(recording.covers(listening))
        XCTAssertFalse(still.covers(recording))
        XCTAssertFalse(still.covers(listening), "A silent stream cannot serve something that listens.")
        XCTAssertTrue(StreamProfile.baseline.covers(.baseline))
        XCTAssertFalse(StreamProfile.baseline.covers(still))
    }

    func testTheSummaryCanBeReadAloud() {
        XCTAssertEqual(StreamProfile.baseline.summary, "504 by 896 at 7 frames a second")
        let recording = StreamProfile(resolution: .high, frameRate: 30, sound: .full, imagesPerSecond: 15)
        XCTAssertEqual(recording.summary, "720 by 1280 at 30 frames a second, sound at 48 kHz")
    }

    func testTheFrameGateThinsAFastStream() {
        var gate = FrameGate(perSecond: 15)
        var admitted = 0
        for frame in 0..<60 {  // two seconds at 30 frames a second
            if gate.admit(at: Double(frame) / 30) { admitted += 1 }
        }
        XCTAssertEqual(admitted, 30)
    }

    func testTheFrameGateLeavesASlowStreamAlone() {
        var gate = FrameGate(perSecond: 7)
        for frame in 0..<14 {
            // Frames a little early or late, as they arrive over Bluetooth.
            let jitter = frame.isMultiple(of: 2) ? 0.01 : -0.01
            XCTAssertTrue(gate.admit(at: Double(frame) / 7 + jitter), "frame \(frame)")
        }
    }

    func testTheFrameGateSurvivesAClockThatStartsAgain() {
        var gate = FrameGate(perSecond: 2)
        XCTAssertTrue(gate.admit(at: 100))
        XCTAssertFalse(gate.admit(at: 100.1))
        XCTAssertTrue(gate.admit(at: 3), "A new stream starts its clock again.")
    }
}

final class CapturePressBufferTests: XCTestCase {
    func testAShortPressWaitsAndIsThenReleased() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.short, at: 10), [])
        XCTAssertEqual(buffer.deadline, 10 + CapturePressBuffer.wait)
        XCTAssertNil(buffer.release(at: 10.2))
        XCTAssertEqual(buffer.release(at: 10.5), .short)
        XCTAssertNil(buffer.release(at: 11), "It is released once.")
        XCTAssertNil(buffer.deadline)
    }

    func testADoublePressReplacesTheShortPressThatCameWithIt() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.short, at: 10), [])
        XCTAssertEqual(buffer.take(.double, at: 10.25), [.double])
        XCTAssertNil(buffer.release(at: 11))
    }

    func testADoublePressAloneStillCounts() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.double, at: 3), [.double])
    }

    func testTwoSeparatePressesAreTwoPresses() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.short, at: 10), [])
        // The timer that releases the first was late, and the second press got here first.
        XCTAssertEqual(buffer.take(.short, at: 12), [.short])
        XCTAssertEqual(buffer.release(at: 12.5), .short)
    }

    func testAHoldIsNotDelayed() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.hold, at: 1), [.hold])
        XCTAssertEqual(buffer.take(.short, at: 5), [])
        XCTAssertEqual(buffer.take(.hold, at: 5.2), [.short, .hold])
        XCTAssertNil(buffer.release(at: 9))
    }

    func testALateDoublePressDoesNotSwallowAnOldShortPress() {
        var buffer = CapturePressBuffer()
        XCTAssertEqual(buffer.take(.short, at: 10), [])
        XCTAssertEqual(buffer.take(.double, at: 11), [.short, .double])
    }
}

final class HeadGestureTests: XCTestCase {
    private typealias Vector = HeadMotion.Vector

    /// Feeds turning about one axis as a sine wave, at 30 readings a second.
    private func run(
        _ detector: inout HeadGestureDetector,
        about axis: Vector,
        gravity: Vector,
        peak: Double,
        swings: Int,
        swingSeconds: Double = 0.25,
        from start: TimeInterval = 0
    ) -> (answer: HeadAnswer?, end: TimeInterval) {
        var answer: HeadAnswer?
        let count = Int(Double(swings) * swingSeconds * 30)
        var time = start
        for step in 0..<count {
            time = start + Double(step) / 30
            let phase = Double(step) / 30 / swingSeconds * Double.pi
            let rate = sin(phase) * peak
            if let found = detector.take(HeadMotion(time: time, turning: axis * rate, acceleration: gravity)) {
                answer = answer ?? found
            }
        }
        return (answer, time + 1.0 / 30)
    }

    private func settled(gravity: Vector) -> HeadGestureDetector {
        var detector = HeadGestureDetector()
        for step in 0..<10 {
            _ = detector.take(HeadMotion(time: Double(step) / 30 - 1, turning: .zero, acceleration: gravity))
        }
        return detector
    }

    private let down = Vector(x: 0, y: -9.81, z: 0)
    private let vertical = Vector(x: 0, y: 1, z: 0)
    private let earToEar = Vector(x: 1, y: 0, z: 0)

    func testTwoNodsMeanYes() {
        var detector = settled(gravity: down)
        XCTAssertEqual(run(&detector, about: earToEar, gravity: down, peak: 2.2, swings: 4).answer, .yes)
    }

    func testAShakeMeansNo() {
        var detector = settled(gravity: down)
        XCTAssertEqual(run(&detector, about: vertical, gravity: down, peak: 3, swings: 3).answer, .no)
    }

    func testTheAnswerDoesNotDependOnHowTheSensorSits() {
        // The sensor turned a quarter turn: gravity is along x, and so is the vertical.
        let sideways = Vector(x: 9.81, y: 0, z: 0)
        var detector = settled(gravity: sideways)
        XCTAssertEqual(run(&detector, about: Vector(x: 1, y: 0, z: 0), gravity: sideways, peak: 3, swings: 3).answer, .no)
        detector = settled(gravity: sideways)
        XCTAssertEqual(run(&detector, about: Vector(x: 0, y: 1, z: 0), gravity: sideways, peak: 2.2, swings: 4).answer, .yes)
        detector = settled(gravity: sideways)
        XCTAssertEqual(run(&detector, about: Vector(x: 0, y: 0, z: 1), gravity: sideways, peak: 2.2, swings: 4).answer, .yes)
    }

    func testOneGlanceToTheSideIsNotAnAnswer() {
        var detector = settled(gravity: down)
        XCTAssertNil(run(&detector, about: vertical, gravity: down, peak: 3, swings: 2).answer)
    }

    func testOneLookDownAndUpIsNotAnAnswer() {
        var detector = settled(gravity: down)
        XCTAssertNil(run(&detector, about: earToEar, gravity: down, peak: 2.5, swings: 2).answer)
    }

    func testWalkingIsNotAnAnswer() {
        var detector = settled(gravity: down)
        // The head bobs with each step, well under the speed of a nod.
        XCTAssertNil(run(&detector, about: earToEar, gravity: down, peak: 0.5, swings: 40).answer)
        XCTAssertNil(run(&detector, about: vertical, gravity: down, peak: 0.6, swings: 40).answer)
    }

    func testSlowSwingsAreNotAnAnswer() {
        var detector = settled(gravity: down)
        // Looking left, then right, then left again, a second each: scanning a street.
        XCTAssertNil(run(&detector, about: vertical, gravity: down, peak: 1.5, swings: 4, swingSeconds: 1.0).answer)
    }

    func testADiagonalTossIsNeitherAnswer() {
        var detector = settled(gravity: down)
        let diagonal = Vector(x: 0.7071, y: 0.7071, z: 0)
        XCTAssertNil(run(&detector, about: diagonal, gravity: down, peak: 3, swings: 6).answer)
    }

    func testNothingIsReadBeforeDownIsKnown() {
        var detector = HeadGestureDetector()
        XCTAssertNil(run(&detector, about: vertical, gravity: down, peak: 3, swings: 1, swingSeconds: 0.1).answer)
        var blind = HeadGestureDetector()
        var answer: HeadAnswer?
        for step in 0..<60 {
            let rate = sin(Double(step) / 30 / 0.25 * Double.pi) * 3
            answer = answer ?? blind.take(HeadMotion(time: Double(step) / 30, turning: vertical * rate, acceleration: nil))
        }
        XCTAssertNil(answer, "Without gravity there is no telling a nod from a shake.")
    }

    func testAShakeThatTurnsIntoANodStartsOver() {
        var detector = settled(gravity: down)
        let first = run(&detector, about: vertical, gravity: down, peak: 3, swings: 2)
        XCTAssertNil(first.answer)
        let second = run(&detector, about: earToEar, gravity: down, peak: 2.2, swings: 2, from: first.end)
        XCTAssertNil(second.answer, "Two swings of each are not three of either.")
    }

    func testOneAnswerPerGesture() {
        var detector = settled(gravity: down)
        var answers = 0
        for step in 0..<Int(0.25 * 3 * 30) {
            let rate = sin(Double(step) / 30 / 0.25 * Double.pi) * 3
            if detector.take(HeadMotion(time: Double(step) / 30, turning: vertical * rate, acceleration: down)) != nil {
                answers += 1
            }
        }
        XCTAssertEqual(answers, 1)
    }
}

final class GlassesSpeechGateTests: XCTestCase {
    private func command(_ text: String, phoneListening: Bool = false) -> String? {
        GlassesSpeechGate.command(in: text, wakeWord: "Jarvis", phoneListening: phoneListening)
    }

    func testASentenceNeedsTheWakeWordAtItsStart() {
        XCTAssertEqual(command("Jarvis, what's on my calendar?"), "what's on my calendar")
        XCTAssertEqual(command("hey jarvis ask Indy about the order"), "ask Indy about the order")
        XCTAssertEqual(command("Uh, Jarvis take a picture."), "take a picture")
        XCTAssertNil(command("what's on my calendar"))
        XCTAssertNil(command("I was telling my brother about Jarvis and what it does"))
    }

    func testOtherPeoplesTalkIsNotACommand() {
        XCTAssertNil(command("Can you pass the salt"))
        XCTAssertNil(command("Call the bank tomorrow and cancel the card"))
    }

    func testTheWakeWordAloneIsNotACommand() {
        XCTAssertNil(command("Jarvis"))
        XCTAssertNil(command("Hey Jarvis."))
        XCTAssertNil(command("   "))
    }

    func testTheWakeWordMustBeAWholeWord() {
        XCTAssertNil(command("Jarvison called about the car"))
    }

    func testTheWakeWordAloneAsksToBeListenedTo() {
        func heard(_ text: String, phoneListening: Bool = false) -> GlassesSpeechGate.Heard {
            GlassesSpeechGate.hear(text, wakeWord: "Jarvis", phoneListening: phoneListening)
        }
        XCTAssertEqual(heard("Jarvis"), .wake)
        XCTAssertEqual(heard("Hey Jarvis."), .wake)
        XCTAssertEqual(heard("Jarvis, read this"), .command("read this"))
        XCTAssertEqual(heard("pass the salt"), .nothing)
        XCTAssertEqual(heard("   "), .nothing)
        // The phone heard it too, and wakes by itself.
        XCTAssertEqual(heard("Jarvis", phoneListening: true), .nothing)
    }

    func testThePhoneHearsItFirstWhenThePhoneIsListening() {
        XCTAssertNil(command("Jarvis, take a picture", phoneListening: true))
    }

    func testAnEmptyWakeWordMatchesNothing() {
        XCTAssertNil(GlassesSpeechGate.command(in: "take a picture", wakeWord: " ", phoneListening: false))
    }

    func testAnotherWakeWordWorksTheSameWay() {
        XCTAssertEqual(
            GlassesSpeechGate.command(in: "Okay Phoenix, read this", wakeWord: "Phoenix", phoneListening: false),
            "read this"
        )
    }
}

final class SessionTroubleTests: XCTestCase {
    func testEveryTroubleHasAdviceThatCanBeSpoken() {
        for trouble in SessionTrouble.allCases {
            XCTAssertFalse(trouble.advice.isEmpty)
            XCTAssertTrue(trouble.advice.hasSuffix("."), "\(trouble)")
            XCTAssertLessThan(trouble.advice.count, 160, "\(trouble)")
        }
    }

    func testOnlySomeTroublesAreWorthTryingAgain() {
        XCTAssertTrue(SessionTrouble.sessionAlreadyExists.worthRetrying)
        XCTAssertFalse(SessionTrouble.thermal.worthRetrying)
        XCTAssertFalse(SessionTrouble.firmwareUpdateRequired.worthRetrying)
        XCTAssertFalse(SessionTrouble.phoneAppTooOld.worthRetrying)
    }
}

final class StreamReplacementTests: XCTestCase {
    private var everything: GlassesCapabilitySettings {
        var glasses = GlassesCapabilitySettings()
        OwnerProfile.apply(to: &glasses)
        return glasses
    }

    func testOnlyTheUsesThatLastRestartACameraThatIsAlreadyOn() {
        XCTAssertTrue(StreamPurpose.guide.replacesLesserStream)
        XCTAssertTrue(StreamPurpose.liveVideo.replacesLesserStream)
        XCTAssertTrue(StreamPurpose.recording.replacesLesserStream)
        XCTAssertFalse(StreamPurpose.still.replacesLesserStream)
        XCTAssertFalse(StreamPurpose.watch.replacesLesserStream)
        XCTAssertFalse(StreamPurpose.smartCapture.replacesLesserStream)
    }

    func testAStreamStartedForOneLookFallsShortOfGuideMode() throws {
        let look = try XCTUnwrap(StreamPlanner.profile(for: .still, capabilities: everything, heat: .normal))
        let guide = try XCTUnwrap(StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal))
        XCTAssertFalse(look.covers(guide), "Seven frames a second is too slow for someone walking.")
        XCTAssertTrue(guide.covers(guide))
    }

    func testARestartTakesNothingAwayFromTheUseThatWasRunning() throws {
        let guide = try XCTUnwrap(StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal, soundWanted: true))
        let live = try XCTUnwrap(StreamPlanner.profile(for: .liveVideo, capabilities: everything, heat: .normal))
        XCTAssertFalse(guide.covers(live))
        let joined = StreamPlanner.replacement(for: live, running: guide, purpose: .liveVideo, heat: .normal)
        XCTAssertTrue(joined.covers(guide), "Guide mode keeps its frame rate and its sound.")
        XCTAssertTrue(joined.covers(live))
        XCTAssertEqual(joined.frameRate, 24)
        XCTAssertEqual(joined.resolution, .high)
        XCTAssertEqual(joined.sound, .speech)
        XCTAssertTrue(StreamPlanner.frameRates.contains(joined.frameRate))
    }

    func testARestartStillObeysTheHeat() throws {
        let guide = try XCTUnwrap(StreamPlanner.profile(for: .guide, capabilities: everything, heat: .normal))
        let live = try XCTUnwrap(StreamPlanner.profile(for: .liveVideo, capabilities: everything, heat: .severe))
        let joined = StreamPlanner.replacement(for: live, running: guide, purpose: .liveVideo, heat: .severe)
        XCTAssertEqual(joined.frameRate, 7)
        XCTAssertEqual(joined.resolution, .medium)
        XCTAssertLessThanOrEqual(joined.imagesPerSecond, Double(joined.frameRate))
    }

    func testAStandardBuildNeverRestartsTheCameraForAnotherUse() throws {
        let standard = GlassesCapabilitySettings()
        let running = try XCTUnwrap(StreamPlanner.profile(for: .still, capabilities: standard, heat: .normal))
        for purpose in [StreamPurpose.guide, .liveVideo, .recording, .watch, .smartCapture] {
            let wanted = try XCTUnwrap(StreamPlanner.profile(for: purpose, capabilities: standard, heat: .normal))
            XCTAssertTrue(running.covers(wanted), "\(purpose.rawValue) asks for the same stream on a standard build.")
        }
    }
}

final class HeadAnswerPolicyTests: XCTestCase {
    func testNothingIsAnsweredWhenNoQuestionWaits() {
        XCTAssertFalse(HeadAnswerPolicy.none.accepts(.yes))
        XCTAssertFalse(HeadAnswerPolicy.none.accepts(.no))
    }

    func testAShakeAlwaysDeclinesAQuestionThatWaits() {
        XCTAssertTrue(HeadAnswerPolicy.noOnly.accepts(.no))
        XCTAssertTrue(HeadAnswerPolicy.yesOrNo.accepts(.no))
    }

    func testANodAgreesOnlyWhereAMistakenYesIsCheap() {
        XCTAssertFalse(HeadAnswerPolicy.noOnly.accepts(.yes))
        XCTAssertTrue(HeadAnswerPolicy.yesOrNo.accepts(.yes))
    }
}

final class RestartPacerTests: XCTestCase {
    func testAStopAfterAWorkingRunIsRestartedAlmostAtOnce() {
        var pacer = RestartPacer()
        pacer.started(at: 100)
        XCTAssertEqual(pacer.stopped(at: 165), RestartPacer.shortest)
        pacer.started(at: 167)
        XCTAssertEqual(pacer.stopped(at: 230), RestartPacer.shortest)
    }

    func testAStartThatKeepsFailingWaitsLongerEachTime() {
        var pacer = RestartPacer()
        var waits: [TimeInterval] = []
        var now: TimeInterval = 0
        for _ in 0..<9 {
            pacer.started(at: now)
            now += 1
            let wait = pacer.stopped(at: now)
            waits.append(wait)
            now += wait
        }
        XCTAssertEqual(waits, [2, 4, 8, 16, 32, 64, 120, 120, 120])
    }

    func testAWorkingRunForgetsEarlierFailures() {
        var pacer = RestartPacer()
        for start in [0.0, 10, 20] {
            pacer.started(at: start)
            _ = pacer.stopped(at: start + 1)
        }
        pacer.started(at: 100)
        XCTAssertEqual(pacer.stopped(at: 100 + RestartPacer.healthyRun), RestartPacer.shortest)
        pacer.started(at: 200)
        XCTAssertEqual(pacer.stopped(at: 201), RestartPacer.shortest)
        pacer.started(at: 210)
        XCTAssertEqual(pacer.stopped(at: 211), RestartPacer.shortest * 2)
    }

    func testAStopThatWasNeverStartedCountsAsAFailure() {
        var pacer = RestartPacer()
        XCTAssertEqual(pacer.stopped(at: 50), 2)
        XCTAssertEqual(pacer.stopped(at: 60), 4)
    }
}
