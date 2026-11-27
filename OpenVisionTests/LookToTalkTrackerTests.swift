// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

/// How a run of looks becomes a choice, what is held, and where requests then go.
final class LookToTalkTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let indy = LookTarget.assistant("Indy")
    private let driver = LookTarget.assistant("Driver")

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func reading(_ entries: (String, Double, LookCandidate.Evidence)...) -> LookReading {
        LookReading(candidates: entries.map { name, score, evidence in
            LookCandidate(target: .assistant(name), score: score, evidence: evidence, box: FrameBox(x: 0, y: 0, width: 0, height: 0))
        })
    }

    private var clear: LookReading { reading(("Indy", 0.9, .title)) }
    private var faint: LookReading { reading(("Indy", 0.5, .mention)) }

    private func tracker(_ change: (inout LookTracker.Rules) -> Void = { _ in }) -> LookTracker {
        var rules = LookTracker.Rules()
        change(&rules)
        return LookTracker(rules: rules)
    }

    /// A tracker that is looking, started at time zero.
    private func looking(_ change: (inout LookTracker.Rules) -> Void = { _ in }) -> LookTracker {
        var tracker = tracker(change)
        _ = tracker.start(at: at(0))
        return tracker
    }

    private func lines(_ effects: [LookTracker.Effect]) -> [String] {
        effects.compactMap { if case .say(let line) = $0 { return line } else { return nil } }
    }

    // MARK: - Finding

    func testItStartsOffAndHoldsNothing() {
        var tracker = tracker()
        XCTAssertTrue(tracker.isOff)
        XCTAssertNil(tracker.held)
        XCTAssertFalse(tracker.wantsCamera)
        XCTAssertEqual(tracker.status, .off)
        XCTAssertEqual(tracker.looked(clear, at: at(1)), [], "Nothing is read while it is off")
        XCTAssertEqual(tracker.tick(at: at(999)), [])
        XCTAssertEqual(tracker.answer(true, at: at(1)), [])
        XCTAssertEqual(tracker.lostCamera(), [])
    }

    func testStartingTurnsTheCameraOnAndSaysSo() {
        var tracker = tracker()
        let effects = tracker.start(at: at(0))
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertTrue(tracker.wantsCamera)
        XCTAssertNil(tracker.held)
        XCTAssertEqual(lines(effects).count, 1)
        XCTAssertTrue(lines(effects)[0].contains("camera light is on"), "The wearer is told the light is on")
    }

    func testOneLookIsNotAChoice() {
        var tracker = looking()
        XCTAssertEqual(tracker.looked(clear, at: at(1)), [])
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertNil(tracker.held)
    }

    func testTwoLooksThatAgreeAreAChoice() {
        var tracker = looking()
        _ = tracker.looked(clear, at: at(1))
        let effects = tracker.looked(clear, at: at(2))
        XCTAssertEqual(effects, [.tone(.locked, indy), .say("Indy, locked."), .listen])
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertEqual(tracker.held, indy)
        XCTAssertFalse(tracker.wantsCamera, "Locked, so the camera can go off")
    }

    func testTheLooksMustBeInARow() {
        var tracker = looking()
        _ = tracker.looked(clear, at: at(1))
        XCTAssertEqual(tracker.looked(.empty, at: at(2)), [])
        XCTAssertEqual(tracker.looked(clear, at: at(3)), [])
        XCTAssertEqual(tracker.looked(reading(("Driver", 0.9, .title)), at: at(4)), [])
        XCTAssertEqual(tracker.looked(clear, at: at(5)), [])
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertFalse(tracker.looked(clear, at: at(6)).isEmpty)
        XCTAssertEqual(tracker.held, indy)
    }

    func testABadgeOrAMarkerNeedsOneLook() {
        for evidence in [LookCandidate.Evidence.badge, .marker] {
            var tracker = looking()
            let effects = tracker.looked(reading(("Indy", 0.6, evidence)), at: at(1))
            XCTAssertEqual(effects.first, .tone(.locked, indy), evidence.rawValue)
            XCTAssertEqual(tracker.held, indy)
        }
    }

    func testMoreLooksCanBeAskedFor() {
        var tracker = looking { $0.dwell = 3 }
        _ = tracker.looked(clear, at: at(1))
        XCTAssertEqual(tracker.looked(clear, at: at(2)), [])
        XCTAssertFalse(tracker.looked(clear, at: at(3)).isEmpty)
    }

    func testWithoutAutoLockItFollows() {
        var tracker = looking { $0.autoLock = false }
        _ = tracker.looked(clear, at: at(1))
        let effects = tracker.looked(clear, at: at(2))
        XCTAssertEqual(effects, [.tone(.found, indy), .say("Indy."), .listen])
        XCTAssertEqual(tracker.state, .following(indy))
        XCTAssertEqual(tracker.held, indy)
        XCTAssertTrue(tracker.wantsCamera, "Following needs to see that the window is still there")
    }

    func testTheMicrophoneCanBeLeftClosed() {
        var tracker = looking { $0.listenAfterTone = false }
        _ = tracker.looked(clear, at: at(1))
        XCTAssertEqual(tracker.looked(clear, at: at(2)), [.tone(.locked, indy), .say("Indy, locked.")])
    }

    // MARK: - Asking

    func testWhenUnsureItAsksOnce() {
        var tracker = looking()
        XCTAssertEqual(tracker.looked(faint, at: at(1)), [])
        let effects = tracker.looked(faint, at: at(2))
        XCTAssertEqual(effects, [.tone(.unsure, indy), .say("Talking to Indy?"), .listen])
        XCTAssertEqual(tracker.state, .asking(indy, other: nil))
        XCTAssertEqual(tracker.question, indy)
        XCTAssertNil(tracker.held, "Nothing is held until the answer")
        XCTAssertTrue(tracker.wantsCamera)
        XCTAssertEqual(tracker.looked(faint, at: at(3)), [], "The question is not asked again while it waits")
        XCTAssertEqual(tracker.looked(faint, at: at(4)), [])
    }

    func testTheQuestionOpensTheMicrophoneWhateverTheSetting() {
        var tracker = looking { $0.listenAfterTone = false }
        _ = tracker.looked(faint, at: at(1))
        XCTAssertEqual(tracker.looked(faint, at: at(2)).last, .listen)
    }

    func testYesTakesTheTarget() {
        var tracker = looking()
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        let effects = tracker.answer(true, at: at(4))
        XCTAssertEqual(effects, [.tone(.locked, indy), .say("Indy, locked."), .listen])
        XCTAssertEqual(tracker.held, indy)
        XCTAssertNil(tracker.question)
    }

    func testNoGoesBackToLookingAndLeavesThatTargetAlone() {
        var tracker = looking()
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        let effects = tracker.answer(false, at: at(4))
        XCTAssertEqual(lines(effects), ["OK. Look at the window again, or say lock on to, and a name."])
        XCTAssertEqual(tracker.state, .searching)
        // Even a clear look at the refused window is ignored for a while.
        for second in 5...12 {
            XCTAssertEqual(tracker.looked(clear, at: at(Double(second))), [])
        }
        XCTAssertNil(tracker.held)
        // Another window is still free to be chosen.
        _ = tracker.looked(reading(("Indy", 0.9, .title), ("Driver", 0.8, .title)), at: at(13))
        XCTAssertFalse(tracker.looked(reading(("Indy", 0.9, .title), ("Driver", 0.8, .title)), at: at(14)).isEmpty)
        XCTAssertEqual(tracker.held, driver)
    }

    func testARefusalWearsOff() {
        var tracker = looking { $0.rest = 10; $0.searchLimit = 600 }
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        _ = tracker.answer(false, at: at(3))
        XCTAssertEqual(tracker.looked(clear, at: at(12)), [])
        _ = tracker.looked(clear, at: at(14))
        XCTAssertFalse(tracker.looked(clear, at: at(15)).isEmpty)
        XCTAssertEqual(tracker.held, indy)
    }

    func testNoToOneOfTwoAsksAboutTheOther() {
        var tracker = looking()
        let between = reading(("Indy", 0.9, .title), ("Driver", 0.85, .title))
        _ = tracker.looked(between, at: at(1))
        XCTAssertEqual(lines(tracker.looked(between, at: at(2))), ["Talking to Indy?"])
        XCTAssertEqual(tracker.state, .asking(indy, other: driver))
        let effects = tracker.answer(false, at: at(3))
        XCTAssertEqual(effects, [.tone(.unsure, driver), .say("Driver?"), .listen])
        XCTAssertEqual(tracker.question, driver)
        XCTAssertEqual(lines(tracker.answer(false, at: at(4))), ["OK. Look at the window again, or say lock on to, and a name."])
        XCTAssertEqual(tracker.state, .searching)
    }

    func testAClearLookAnswersTheQuestion() {
        var tracker = looking()
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        // The looks before it were at the same window, so one clear look settles it.
        XCTAssertEqual(tracker.looked(clear, at: at(3)), [.tone(.locked, indy), .say("Indy, locked."), .listen])
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertNil(tracker.question)
    }

    func testAQuestionNobodyAnswersIsDroppedAndNotRepeated() {
        var tracker = looking()
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        XCTAssertEqual(tracker.tick(at: at(9)), [], "Still waiting")
        XCTAssertEqual(tracker.question, indy)
        XCTAssertEqual(tracker.tick(at: at(11)), [], "Dropped without a word")
        XCTAssertEqual(tracker.state, .searching)
        // The same faint look does not bring the question back.
        for second in 12...20 {
            XCTAssertEqual(tracker.looked(faint, at: at(Double(second))), [])
        }
        // Silence was not a no: a clear look still takes it.
        XCTAssertFalse(tracker.looked(clear, at: at(21)).isEmpty)
        XCTAssertEqual(tracker.held, indy)
    }

    func testAFaintLookThenAClearOneAtTheSameWindowAgree() {
        var tracker = looking()
        XCTAssertEqual(tracker.looked(faint, at: at(1)), [])
        XCTAssertEqual(tracker.looked(clear, at: at(2)).first, .tone(.locked, indy))
    }

    func testAnAnswerWithNoQuestionDoesNothing() {
        var tracker = looking()
        XCTAssertEqual(tracker.answer(true, at: at(1)), [])
        XCTAssertEqual(tracker.answer(false, at: at(1)), [])
        XCTAssertEqual(tracker.state, .searching)
    }

    // MARK: - Following

    private func following() -> LookTracker {
        var tracker = looking { $0.autoLock = false }
        _ = tracker.looked(clear, at: at(1))
        _ = tracker.looked(clear, at: at(2))
        return tracker
    }

    func testAFollowedTargetIsKeptWhileItIsInView() {
        var tracker = following()
        for second in 3...40 {
            // Only plausible is enough once it is held.
            XCTAssertEqual(tracker.looked(faint, at: at(Double(second))), [])
            XCTAssertEqual(tracker.tick(at: at(Double(second))), [])
        }
        XCTAssertEqual(tracker.state, .following(indy))
    }

    func testAFollowedTargetIsLetGoWhenTheWearerLooksAway() {
        var tracker = following()
        XCTAssertEqual(tracker.looked(.empty, at: at(3)), [])
        XCTAssertEqual(tracker.tick(at: at(6)), [], "A glance away is forgiven")
        XCTAssertEqual(tracker.held, indy)
        XCTAssertEqual(tracker.looked(.empty, at: at(7)), [])
        XCTAssertEqual(tracker.tick(at: at(8)), [.tone(.released, indy)])
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertNil(tracker.held)
        // And found again by looking back.
        _ = tracker.looked(clear, at: at(9))
        XCTAssertEqual(tracker.looked(clear, at: at(10)).first, .tone(.found, indy))
    }

    func testLookingAtAnotherWindowMovesTheTarget() {
        var tracker = following()
        let other = reading(("Driver", 0.9, .title), ("Indy", 0.5, .mention))
        XCTAssertEqual(tracker.looked(other, at: at(3)), [])
        XCTAssertEqual(tracker.looked(other, at: at(4)), [.tone(.found, driver), .say("Driver."), .listen])
        XCTAssertEqual(tracker.state, .following(driver))
    }

    func testAnotherWindowMustBeClearerToTakeOver() {
        var tracker = following()
        // Both are in view and neither leads: the one held stays.
        let both = reading(("Driver", 0.9, .title), ("Indy", 0.85, .title))
        for second in 3...8 {
            XCTAssertEqual(tracker.looked(both, at: at(Double(second))), [])
        }
        XCTAssertEqual(tracker.state, .following(indy))
        // Nothing is asked while something is held.
        XCTAssertNil(tracker.question)
    }

    func testFollowingForALongTimeLocksToSaveTheBattery() {
        var tracker = looking { $0.autoLock = false; $0.followLimit = 60 }
        _ = tracker.looked(clear, at: at(1))
        _ = tracker.looked(clear, at: at(2))
        for second in 3...62 { _ = tracker.looked(clear, at: at(Double(second))) }
        XCTAssertEqual(tracker.tick(at: at(61)), [])
        let effects = tracker.tick(at: at(63))
        XCTAssertEqual(effects.first, .tone(.locked, indy))
        XCTAssertEqual(lines(effects), ["The camera is off to save the battery. Still locked on to Indy."])
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertFalse(tracker.wantsCamera)
    }

    // MARK: - Locking

    func testLockOnHoldsWhatIsFollowed() {
        var tracker = following()
        XCTAssertEqual(tracker.lock(nil, at: at(3)), [.tone(.locked, indy), .say("Locked on to Indy.")])
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertFalse(tracker.wantsCamera)
        XCTAssertEqual(lines(tracker.lock(nil, at: at(4))), ["Already locked on to Indy."])
    }

    func testLockOnAnswersTheQuestion() {
        var tracker = looking()
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        XCTAssertEqual(lines(tracker.lock(nil, at: at(3))), ["Locked on to Indy."])
        XCTAssertEqual(tracker.held, indy)
    }

    func testANameLocksWithoutTheCamera() {
        var tracker = tracker()
        XCTAssertEqual(tracker.lock(driver, at: at(0)), [.tone(.locked, driver), .say("Locked on to Driver.")])
        XCTAssertEqual(tracker.state, .locked(driver))
        XCTAssertFalse(tracker.wantsCamera)
        // And replaces whatever was held or being looked for.
        XCTAssertEqual(lines(tracker.lock(indy, at: at(1))), ["Locked on to Indy."])
        XCTAssertEqual(tracker.held, indy)
        var searching = looking()
        _ = searching.lock(driver, at: at(1))
        XCTAssertEqual(searching.state, .locked(driver))
    }

    func testLockOnWithNothingInViewSaysWhatToDo() {
        var off = tracker()
        XCTAssertEqual(lines(off.lock(nil, at: at(0))), ["Look to Talk is off. Say look to talk, or say lock on to, and a name."])
        XCTAssertTrue(off.isOff)
        var searching = looking()
        XCTAssertEqual(lines(searching.lock(nil, at: at(1))), ["I'm not looking at an assistant yet. Say lock on to, and a name."])
        XCTAssertEqual(searching.state, .searching)
    }

    func testALockIgnoresWhatTheCameraSees() {
        var tracker = tracker()
        _ = tracker.lock(indy, at: at(0))
        XCTAssertEqual(tracker.looked(reading(("Driver", 1, .badge)), at: at(1)), [])
        XCTAssertEqual(tracker.held, indy)
    }

    func testALockThatIsNotUsedEnds() {
        var tracker = tracker { $0.lockLife = 600 }
        _ = tracker.lock(indy, at: at(0))
        XCTAssertEqual(tracker.tick(at: at(599)), [])
        XCTAssertEqual(tracker.tick(at: at(601)), [.tone(.released, indy), .say("Let go of Indy.")])
        XCTAssertTrue(tracker.isOff)
        XCTAssertNil(tracker.held)
    }

    func testUsingALockKeepsIt() {
        var tracker = tracker { $0.lockLife = 600 }
        _ = tracker.lock(indy, at: at(0))
        tracker.used(at: at(500))
        XCTAssertEqual(tracker.tick(at: at(1_000)), [])
        XCTAssertEqual(tracker.held, indy)
        XCTAssertFalse(tracker.tick(at: at(1_101)).isEmpty)
        XCTAssertTrue(tracker.isOff)
    }

    // MARK: - Looking again

    func testLookingAgainKeepsTheLockUntilAnotherIsFound() {
        var tracker = tracker()
        _ = tracker.lock(indy, at: at(0))
        XCTAssertEqual(lines(tracker.start(at: at(10))), ["Looking again, and the camera light is on."])
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertTrue(tracker.wantsCamera)
        XCTAssertEqual(tracker.held, indy, "Requests still go to Indy meanwhile")
        XCTAssertEqual(tracker.status, .searching(kept: "Indy"))

        let other = reading(("Driver", 0.9, .title))
        _ = tracker.looked(other, at: at(11))
        XCTAssertEqual(tracker.looked(other, at: at(12)).first, .tone(.locked, driver))
        XCTAssertEqual(tracker.held, driver)
    }

    func testLookingAgainAndFindingNothingGoesBackToTheLock() {
        var tracker = tracker { $0.searchLimit = 45; $0.lockLife = 600 }
        _ = tracker.lock(indy, at: at(0))
        _ = tracker.start(at: at(100))
        XCTAssertEqual(tracker.tick(at: at(140)), [])
        XCTAssertEqual(lines(tracker.tick(at: at(146))), ["I can't see another assistant's window. Still locked on to Indy."])
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertFalse(tracker.wantsCamera)
        // The lock's life is still counted from when it was last used, not from the look.
        XCTAssertFalse(tracker.tick(at: at(601)).isEmpty)
        XCTAssertTrue(tracker.isOff)
    }

    func testARequestSentWhileLookingAgainKeepsTheOldLockAlive() {
        var tracker = tracker { $0.lockLife = 600 }
        _ = tracker.lock(indy, at: at(0))
        _ = tracker.start(at: at(580))
        tracker.used(at: at(590))
        _ = tracker.tick(at: at(626))
        XCTAssertEqual(tracker.state, .locked(indy))
        XCTAssertEqual(tracker.tick(at: at(1_100)), [])
        XCTAssertEqual(tracker.held, indy)
    }

    func testLockOnWhileLookingAgainKeepsTheOldLock() {
        var tracker = tracker()
        _ = tracker.lock(indy, at: at(0))
        _ = tracker.start(at: at(10))
        XCTAssertEqual(lines(tracker.lock(nil, at: at(12))), ["Still locked on to Indy."])
        XCTAssertEqual(tracker.state, .locked(indy))
    }

    func testAskingForLookToTalkTwiceGivesMoreTime() {
        var tracker = looking { $0.searchLimit = 45 }
        XCTAssertEqual(lines(tracker.start(at: at(40))).count, 1)
        XCTAssertEqual(tracker.state, .searching)
        XCTAssertEqual(tracker.tick(at: at(80)), [], "The count began again at forty seconds")
        XCTAssertFalse(tracker.tick(at: at(86)).isEmpty)
    }

    func testStartingWhileFollowingSaysWhoIsInView() {
        var tracker = following()
        XCTAssertEqual(lines(tracker.start(at: at(3))), ["You're looking at Indy. Say lock on to keep it when you look away."])
        XCTAssertEqual(tracker.state, .following(indy))
    }

    // MARK: - Giving up and letting go

    func testItGivesUpWhenNoWindowIsFound() {
        var tracker = looking { $0.searchLimit = 45 }
        for second in 1...45 {
            _ = tracker.looked(.empty, at: at(Double(second)))
            XCTAssertEqual(tracker.tick(at: at(Double(second))), [])
        }
        let effects = tracker.tick(at: at(46))
        XCTAssertEqual(effects.first, .tone(.released, nil))
        XCTAssertEqual(lines(effects).count, 1)
        XCTAssertTrue(lines(effects)[0].contains("Look to Talk is off"))
        XCTAssertTrue(tracker.isOff)
        XCTAssertFalse(tracker.wantsCamera, "The camera does not stay on looking for nothing")
    }

    func testLettingGoEndsEverything() {
        var locked = tracker()
        _ = locked.lock(indy, at: at(0))
        XCTAssertEqual(locked.release(), [.tone(.released, indy), .say("Let go of Indy.")])
        XCTAssertTrue(locked.isOff)
        XCTAssertNil(locked.held)

        var followed = following()
        XCTAssertEqual(followed.release().first, .tone(.released, indy))
        XCTAssertFalse(followed.wantsCamera)

        var searching = looking()
        XCTAssertEqual(searching.release(), [.say("Look to Talk is off.")])
        XCTAssertTrue(searching.isOff)

        var off = tracker()
        XCTAssertEqual(off.release(), [.say("Look to Talk is already off.")])
    }

    func testLettingGoWhileLookingAgainDropsTheOldLockToo() {
        var tracker = tracker()
        _ = tracker.lock(indy, at: at(0))
        _ = tracker.start(at: at(5))
        XCTAssertEqual(tracker.release(), [.tone(.released, indy), .say("Let go of Indy.")])
        XCTAssertNil(tracker.held)
        _ = tracker.start(at: at(10))
        XCTAssertNil(tracker.held, "A new start does not bring it back")
    }

    func testLosingTheCameraEndsTheLookAndKeepsALock() {
        var searching = looking()
        let effects = searching.lostCamera()
        XCTAssertEqual(effects.first, .tone(.released, nil))
        XCTAssertEqual(lines(effects), ["I've lost the glasses camera, so Look to Talk is off."])
        XCTAssertTrue(searching.isOff)

        var again = tracker()
        _ = again.lock(indy, at: at(0))
        _ = again.start(at: at(5))
        XCTAssertEqual(lines(again.lostCamera()), ["I've lost the glasses camera. Still locked on to Indy."])
        XCTAssertEqual(again.state, .locked(indy))

        var locked = tracker()
        _ = locked.lock(indy, at: at(0))
        XCTAssertEqual(locked.lostCamera(), [], "A lock does not need the camera")
        XCTAssertEqual(locked.held, indy)
    }

    func testTheCameraIsWantedOnlyWhileLooking() {
        var tracker = tracker()
        XCTAssertFalse(tracker.wantsCamera)
        _ = tracker.start(at: at(0))
        XCTAssertTrue(tracker.wantsCamera)
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        XCTAssertTrue(tracker.wantsCamera, "Still looking while the question waits")
        _ = tracker.answer(true, at: at(3))
        XCTAssertFalse(tracker.wantsCamera)
        _ = tracker.release()
        XCTAssertFalse(tracker.wantsCamera)
    }

    // MARK: - What the phone shows and says

    func testStatusSaysWhatIsHappening() {
        XCTAssertEqual(LookStatus.off.title, "Look to Talk is off")
        XCTAssertEqual(LookStatus.searching(kept: nil).title, "Looking for a window")
        XCTAssertEqual(LookStatus.searching(kept: "Indy").title, "Looking again. Still Indy")
        XCTAssertEqual(LookStatus.asking("Indy").title, "Talking to Indy?")
        XCTAssertEqual(LookStatus.following("Indy").title, "Looking at Indy")
        XCTAssertEqual(LookStatus.locked("Indy").title, "Locked on to Indy")

        XCTAssertNil(LookStatus.off.name)
        XCTAssertNil(LookStatus.searching(kept: nil).name)
        XCTAssertNil(LookStatus.asking("Indy").name, "A question is not yet a choice")
        XCTAssertEqual(LookStatus.searching(kept: "Indy").name, "Indy")
        XCTAssertEqual(LookStatus.following("Indy").name, "Indy")
        XCTAssertEqual(LookStatus.locked("Indy").name, "Indy")

        let all: [LookStatus] = [.off, .searching(kept: nil), .searching(kept: "Indy"), .asking("Indy"), .following("Indy"), .locked("Indy")]
        XCTAssertEqual(all.map(\.cameraOn), [false, true, true, true, true, false])
        XCTAssertTrue(all.allSatisfy { !$0.symbol.isEmpty })
        XCTAssertEqual(Set(all.map { $0.spoken(usual: "Fire Fox") }).count, all.count)
        XCTAssertTrue(LookStatus.off.spoken(usual: "Fire Fox").contains("Fire Fox"))
        XCTAssertTrue(LookStatus.locked("Indy").spoken(usual: "Fire Fox").contains("locked on to Indy"))
    }

    func testTheStatusFollowsTheTracker() {
        var tracker = looking { $0.autoLock = false }
        XCTAssertEqual(tracker.status, .searching(kept: nil))
        _ = tracker.looked(faint, at: at(1))
        _ = tracker.looked(faint, at: at(2))
        XCTAssertEqual(tracker.status, .asking("Indy"))
        _ = tracker.answer(true, at: at(3))
        XCTAssertEqual(tracker.status, .following("Indy"))
        _ = tracker.lock(nil, at: at(4))
        XCTAssertEqual(tracker.status, .locked("Indy"))
        XCTAssertEqual(tracker.status.cameraOn, tracker.wantsCamera)
        _ = tracker.release()
        XCTAssertEqual(tracker.status, .off)
    }

    // MARK: - One look for one request

    func testOneLookSendsWhenItIsClear() {
        var badge = LookOnce()
        XCTAssertEqual(badge.looked(reading(("Indy", 0.6, .badge))), .send(indy))

        var title = LookOnce()
        XCTAssertNil(title.looked(clear), "One look at a title is not enough")
        XCTAssertEqual(title.looked(clear), .send(indy))
    }

    func testOneLookNeedsTheSameWindowTwice() {
        var look = LookOnce()
        XCTAssertNil(look.looked(clear))
        XCTAssertNil(look.looked(reading(("Driver", 0.9, .title))))
        XCTAssertEqual(look.looked(reading(("Driver", 0.9, .title))), .send(driver))
    }

    func testOneLookAsksWhenItIsNotClear() {
        var look = LookOnce()
        XCTAssertNil(look.looked(faint))
        XCTAssertNil(look.looked(.empty))
        XCTAssertNil(look.looked(faint))
        XCTAssertEqual(look.looked(faint), .ask(indy))

        // One clear frame among blurred ones is still only worth a question.
        var blurred = LookOnce()
        XCTAssertNil(blurred.looked(clear))
        XCTAssertNil(blurred.looked(.empty))
        XCTAssertNil(blurred.looked(.empty))
        XCTAssertEqual(blurred.looked(.empty), .ask(indy))
    }

    func testOneLookAsksAboutTheBestOfWhatItSaw() {
        var look = LookOnce()
        _ = look.looked(reading(("Driver", 0.5, .mention)))
        _ = look.looked(reading(("Indy", 0.6, .mention)))
        _ = look.looked(reading(("Driver", 0.45, .mention)))
        XCTAssertEqual(look.looked(.empty), .ask(indy))
    }

    func testOneLookThatSeesNothingSaysSo() {
        var look = LookOnce()
        for _ in 1..<LookOnce.looks { XCTAssertNil(look.looked(.empty)) }
        XCTAssertEqual(look.looked(.empty), .nothing)
    }

    // MARK: - Commands

    private let names = ["Fire Fox", "Indy", "Driver", "Rally"]

    private func parse(_ said: String, active: Bool = false, asking: Bool = false, enabled: Bool = true) -> LookCommand? {
        LookCommand.parse(said, context: LookCommand.Context(enabled: enabled, bots: names, active: active, asking: asking))
    }

    func testNothingMatchesWithTheSwitchOff() {
        let phrases = ["look to talk", "lock on to Indy", "ask this one to check the build", "who am I talking to",
                       "let go", "yes", "stop look to talk", "look again"]
        for phrase in phrases {
            XCTAssertNil(parse(phrase, active: true, asking: true, enabled: false), phrase)
        }
        XCTAssertNil(LookCommand.parse("look to talk", context: LookCommand.Context()), "Off is the default")
    }

    func testStartingAndStopping() {
        for phrase in ["look to talk", "Look to Talk.", "Hey Phoenix, look to talk", "start look to talk please", "turn on look to talk"] {
            XCTAssertEqual(parse(phrase), .start, phrase)
        }
        for phrase in ["stop look to talk", "turn off look to talk", "look to talk off", "Phoenix, end look to talk"] {
            XCTAssertEqual(parse(phrase), .stop, phrase)
        }
    }

    func testWhoAmITalkingTo() {
        XCTAssertEqual(parse("who am I talking to"), .who)
        XCTAssertEqual(parse("Who am I talking to?"), .who)
        XCTAssertEqual(parse("who's listening"), .who)
    }

    func testLockingOnByName() {
        XCTAssertEqual(parse("lock on to Indy"), .lock("Indy"))
        XCTAssertEqual(parse("lock onto driver"), .lock("Driver"))
        XCTAssertEqual(parse("Phoenix, lock on Rally"), .lock("Rally"))
        XCTAssertEqual(parse("switch to fire fox"), .lock("Fire Fox"))
        XCTAssertEqual(parse("talk to Indy please"), .lock("Indy"))
        XCTAssertEqual(parse("stay with Driver"), .lock("Driver"))
        // The recognizer writes the browser's name. The wearer meant the assistant.
        XCTAssertEqual(parse("lock on to Firefox"), .lock("Fire Fox"))
        XCTAssertEqual(parse("switch to FireFox"), .lock("Fire Fox"))
    }

    func testANameThatIsNotAnAssistantIsNotACommand() {
        XCTAssertNil(parse("lock on to Bob"))
        XCTAssertNil(parse("talk to my sister about Sunday"))
        XCTAssertNil(parse("switch to the other tab"))
        XCTAssertNil(parse("lock on to Bob", active: true))
        XCTAssertNil(parse("talk to Indy about the gate"), "A request, not a lock")
    }

    func testOneRequestForTheWindowInView() {
        XCTAssertEqual(parse("ask this one to check the build"), .once("check the build"))
        XCTAssertEqual(parse("tell that one that the build is green"), .once("the build is green"))
        XCTAssertEqual(parse("ask this bot how the tests went"), .once("how the tests went"))
        XCTAssertEqual(parse("Hey Phoenix, ask this assistant to draft a reply to Sam"), .once("draft a reply to Sam"))
        XCTAssertEqual(parse("tell this window to stop"), .once("stop"))
        XCTAssertNil(parse("ask this one"), "With no request there is nothing to send")
        XCTAssertNil(parse("ask Indy to check the build"), "A named request goes on as it always did")
    }

    func testWhatIsOnlyUnderstoodWhileItIsRunning() {
        let cases: [(String, LookCommand)] = [
            ("lock on", .lock(nil)), ("lock", .lock(nil)), ("hold that", .lock(nil)), ("stay with this one", .lock(nil)),
            ("let go", .unlock), ("unlock", .unlock), ("release", .unlock), ("stop looking", .unlock),
            ("let go of Indy", .unlock), ("stop talking to Driver", .unlock),
            ("look again", .again), ("pick again", .again),
        ]
        for (phrase, command) in cases {
            XCTAssertEqual(parse(phrase, active: true), command, phrase)
            XCTAssertNil(parse(phrase), "\(phrase) means nothing while Look to Talk is off")
        }
    }

    func testAnswersAreOnlyHeardWhenAQuestionWaits() {
        for phrase in ["yes", "Yes.", "yeah", "that's right", "correct"] {
            XCTAssertEqual(parse(phrase, active: true, asking: true), .yes, phrase)
            XCTAssertNil(parse(phrase, active: true), phrase)
        }
        for phrase in ["no", "No.", "nope", "not that one", "wrong"] {
            XCTAssertEqual(parse(phrase, active: true, asking: true), .no, phrase)
            XCTAssertNil(parse(phrase, active: true), phrase)
        }
        // A name answers better than yes or no.
        XCTAssertEqual(parse("Driver", active: true, asking: true), .lock("Driver"))
        XCTAssertEqual(parse("firefox", active: true, asking: true), .lock("Fire Fox"))
        XCTAssertNil(parse("Driver", active: true))
    }

    func testOrdinarySentencesGoOnToTheAssistant() {
        let phrases = ["what's the weather", "look at this", "lock the front door", "what time is it",
                       "look to talk to the manager", "tell this to everyone", "ask Indy about the gate",
                       "let go of the rope", "release notes for version two", "yes please send it", ""]
        for phrase in phrases {
            XCTAssertNil(parse(phrase, active: true), phrase)
        }
    }

    // MARK: - Settings

    func testItIsOffUntilItsOwnSwitchIsTurnedOn() {
        let fresh = WorkshopSettings()
        XCTAssertFalse(fresh.lookToTalk)
        XCTAssertTrue(fresh.lookAutoLock)
        XCTAssertTrue(fresh.lookListenAfterTone)
        XCTAssertEqual(fresh.lookLockMinutes, 10)
        XCTAssertTrue(fresh.lookOtherNames.isEmpty)

        var owner = WorkshopSettings()
        OwnerProfile.apply(to: &owner)
        XCTAssertFalse(owner.lookToTalk, "The owner build's profile leaves it off until the first release is stable")
    }

    func testItRunsOnlyInTheOwnerBuild() {
        var settings = WorkshopSettings()
        settings.lookToTalk = true
        settings.lookAutoLock = false
        settings.lookListenAfterTone = false
        settings.lookLockMinutes = 30
        settings.lookOtherNames = ["indy": "indy_bot"]
        XCTAssertTrue(settings.allowed(in: .owner).lookToTalk)
        let standard = settings.allowed(in: .standard)
        XCTAssertFalse(standard.lookToTalk)
        // What the wearer chose is kept for the day the switch may be used.
        XCTAssertFalse(standard.lookAutoLock)
        XCTAssertFalse(standard.lookListenAfterTone)
        XCTAssertEqual(standard.lookLockMinutes, 30)
        XCTAssertEqual(standard.lookOtherNames, ["indy": "indy_bot"])
    }

    func testItIsNotOneOfTheTen() {
        var settings = WorkshopSettings()
        settings.lookToTalk = true
        XCTAssertFalse(settings.anyOn)
    }

    func testSettingsSavedBeforeItExistedStillLoad() throws {
        let old = Data(#"{"walkThrough":true,"doseGapHours":6}"#.utf8)
        let settings = try JSONDecoder().decode(WorkshopSettings.self, from: old)
        XCTAssertTrue(settings.walkThrough)
        XCTAssertFalse(settings.lookToTalk)
        XCTAssertTrue(settings.lookAutoLock)
        XCTAssertTrue(settings.lookListenAfterTone)
        XCTAssertEqual(settings.lookLockMinutes, 10)
        XCTAssertEqual(settings.lookOtherNames, [:])
    }

    func testSettingsSurviveBeingSaved() throws {
        var settings = WorkshopSettings()
        settings.lookToTalk = true
        settings.lookAutoLock = false
        settings.lookListenAfterTone = false
        settings.lookLockMinutes = 25
        settings.lookOtherNames = ["indy": "indy_bot, Indiana"]
        let loaded = try JSONDecoder().decode(WorkshopSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(loaded, settings)
    }

    func testALockTimeOutOfRangeIsPutBack() throws {
        for minutes in ["0", "-5", "600", "\"soon\""] {
            let data = Data(#"{"lookToTalk":true,"lookLockMinutes":\#(minutes)}"#.utf8)
            let settings = try JSONDecoder().decode(WorkshopSettings.self, from: data)
            XCTAssertEqual(settings.lookLockMinutes, 10, minutes)
            XCTAssertTrue(settings.lookToTalk)
        }
        XCTAssertEqual(WorkshopSettings.lockRange, 1...60)
    }

    func testTheRulesComeFromTheSettings() {
        var settings = WorkshopSettings()
        XCTAssertEqual(settings.lookRules, LookTracker.Rules())
        settings.lookAutoLock = false
        settings.lookListenAfterTone = false
        settings.lookLockMinutes = 2
        XCTAssertFalse(settings.lookRules.autoLock)
        XCTAssertFalse(settings.lookRules.listenAfterTone)
        XCTAssertEqual(settings.lookRules.lockLife, 120)
    }

    func testOtherNamesAreSplitAtCommas() {
        var settings = WorkshopSettings()
        settings.lookOtherNames = ["indy": " indy_bot ,Indiana,, ", "driver": "   ", "gone": "Nobody"]
        let names = settings.lookNames(for: AssistantRoster.seed)
        XCTAssertEqual(names.map(\.bot), AssistantRoster.seed.map(\.name))
        XCTAssertEqual(names.first { $0.bot == "Indy" }?.others, ["indy_bot", "Indiana"])
        XCTAssertEqual(names.first { $0.bot == "Driver" }?.others, [])
        XCTAssertEqual(names.first { $0.bot == "Fire Fox" }?.others, [])
    }

    // MARK: - Where requests go

    private func context(focus: String?, fastMode: Bool = false, isPro: Bool = true, instantReady: Bool = false) -> FastModeRouter.Context {
        FastModeRouter.Context(
            fastMode: fastMode, isPro: isPro, bots: AssistantRoster.seed, instantReady: instantReady, clipEnabled: false, focus: focus
        )
    }

    private func relayed(_ said: String, _ context: FastModeRouter.Context, file: StaticString = #filePath, line: UInt = #line) -> RelayTurn? {
        guard case .relay(let turn) = FastModeRouter.rules(said, context: context) else {
            XCTFail("\(said) should go to the relay", file: file, line: line)
            return nil
        }
        return turn
    }

    func testWithNothingHeldRequestsGoWhereTheyAlwaysDid() {
        let plain = FastModeRouter.Context(fastMode: false, isPro: true, bots: AssistantRoster.seed, instantReady: false, clipEnabled: false)
        XCTAssertNil(plain.focus)
        XCTAssertNil(FastModeRouter.focus(in: plain))
        for said in ["how did the tests go", "ask Indy about the gate", "look at this", "brief me"] {
            XCTAssertEqual(FastModeRouter.rules(said, context: plain), FastModeRouter.rules(said, context: context(focus: nil)), said)
        }
        XCTAssertEqual(relayed("how did the tests go", plain)?.targetBot, "Fire Fox")
    }

    func testARequestThatNamesNobodyGoesToTheHeldAssistant() {
        let held = context(focus: "Indy")
        XCTAssertEqual(relayed("how did the tests go", held)?.targetBot, "Indy")
        XCTAssertEqual(relayed("how did the tests go", held)?.text, "how did the tests go")
        XCTAssertEqual(relayed("book a table for two", held)?.targetBot, "Indy")
        XCTAssertEqual(relayed("brief me", held)?.targetBot, "Indy")
        XCTAssertEqual(relayed("how did the tests go", context(focus: " indy "))?.targetBot, "Indy", "As the roster spells it")
    }

    func testANameSaidAloudStillWins() {
        let held = context(focus: "Indy")
        XCTAssertEqual(relayed("ask Driver to check the gate", held)?.targetBot, "Driver")
        XCTAssertEqual(relayed("tell Fire Fox the build is green", held)?.targetBot, "Fire Fox")
    }

    func testTheHeldAssistantIsNeverAnsweredForByTheQuickModel() {
        let quick = context(focus: nil, fastMode: true, instantReady: true)
        guard case .instant = FastModeRouter.rules("how tall is the Eiffel Tower", context: quick) else {
            return XCTFail("With nothing held, the quick model answers")
        }
        let held = context(focus: "Indy", fastMode: true, instantReady: true)
        XCTAssertEqual(relayed("how tall is the Eiffel Tower", held)?.targetBot, "Indy")
        XCTAssertEqual(relayed("what am I looking at", held)?.targetBot, "Indy")
        // The default assistant held by a look is also asked, not the quick model.
        let usual = context(focus: "Fire Fox", fastMode: true, instantReady: true)
        XCTAssertEqual(relayed("how tall is the Eiffel Tower", usual)?.targetBot, "Fire Fox")
    }

    func testLookAtThisSendsThePhotoToTheHeldAssistant() {
        let turn = relayed("look at this", context(focus: "Driver"))
        XCTAssertEqual(turn?.targetBot, "Driver")
        XCTAssertEqual(turn?.photo, true)
        XCTAssertEqual(turn?.intent, "look")
        XCTAssertEqual(relayed("what does this say", context(focus: "Driver"))?.photo, true)
    }

    func testAHeldNameThatIsNotOnTheRosterIsIgnored() {
        XCTAssertNil(FastModeRouter.focus(in: context(focus: "Nobody")))
        XCTAssertNil(FastModeRouter.focus(in: context(focus: "")))
        XCTAssertNil(FastModeRouter.focus(in: context(focus: "   ")))
        XCTAssertEqual(relayed("how did the tests go", context(focus: "Nobody"))?.targetBot, "Fire Fox")
    }

    func testAPlanWithOneAssistantCanOnlyHoldThatOne() {
        XCTAssertNil(FastModeRouter.focus(in: context(focus: "Indy", isPro: false)))
        XCTAssertEqual(FastModeRouter.focus(in: context(focus: "Fire Fox", isPro: false))?.name, "Fire Fox")
        XCTAssertEqual(relayed("how did the tests go", context(focus: "Indy", isPro: false))?.targetBot, "Fire Fox")
    }

    func testEveryoneStillMeansEveryone() {
        XCTAssertEqual(relayed("status report", context(focus: "Indy"))?.targetBot, AssistantBot.allBots)
    }
}
