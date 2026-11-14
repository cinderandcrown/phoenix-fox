// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class AccessCommandTests: XCTestCase {
    private func parse(_ text: String, focus: AccessCommand.Focus = .none, guiding: Bool = false, walking: Bool = false) -> AccessCommand? {
        AccessCommand.parse(text, context: .init(focus: focus, guiding: guiding, walking: walking))
    }

    func testSeeing() {
        XCTAssertEqual(parse("Read this."), .read(.everything))
        XCTAssertEqual(parse("Jarvis, can you read this to me?"), .read(.everything))
        XCTAssertEqual(parse("read the menu"), .read(.everything))
        XCTAssertEqual(parse("What does this say?"), .read(.everything))
        XCTAssertEqual(parse("read the sign"), .read(.sign))
        XCTAssertEqual(parse("what does that sign say"), .read(.sign))
        XCTAssertEqual(parse("Read the label"), .readLabel)
        XCTAssertEqual(parse("what medication is this"), .readLabel)
        XCTAssertEqual(parse("which pills are these"), .readLabel)
        XCTAssertEqual(parse("What bill is this?"), .identifyMoney)
        XCTAssertEqual(parse("how much money is this"), .identifyMoney)
        XCTAssertEqual(parse("what color is this shirt"), .identifyColor)
        XCTAssertEqual(parse("What colour am I holding?"), .identifyColor)
        XCTAssertEqual(parse("describe the scene"), .describeScene)
        XCTAssertEqual(parse("what's in front of me"), .describeScene)
    }

    func testFindingNeedsSomethingTheCameraCanSee() {
        XCTAssertEqual(parse("where's the door"), .find("door"))
        XCTAssertEqual(parse("find the exit"), .find("exit"))
        XCTAssertEqual(parse("is there a chair nearby"), .find("chair"))
        // Outside Guide mode, an unknown thing is a question for the assistant.
        XCTAssertNil(parse("find the nearest coffee shop"))
        XCTAssertNil(parse("find a recipe for soup"))
        XCTAssertEqual(parse("find the vending machine", guiding: true), .find("vending machine"))
    }

    func testFaces() {
        XCTAssertEqual(parse("who is this"), .whoIsThis)
        XCTAssertEqual(parse("Who's in front of me?"), .whoIsThis)
        XCTAssertEqual(parse("remember this person as sam taylor"), .rememberFace(name: "Sam Taylor"))
        XCTAssertEqual(parse("forget Sam's face"), .forgetFace(name: "Sam"))
        XCTAssertEqual(parse("forget all faces"), .forgetAllFaces)
        XCTAssertEqual(parse("turn on face recognition"), .faceRecognition(true))
        XCTAssertEqual(parse("face recognition off"), .faceRecognition(false))
    }

    func testGettingAround() {
        XCTAssertEqual(parse("start guide mode"), .guide(true))
        XCTAssertEqual(parse("Guide mode off"), .guide(false))
        XCTAssertEqual(parse("guide me"), .guide(true))
        XCTAssertEqual(parse("walk me to the pharmacy on main street"), .walk(to: "the pharmacy on main street"))
        XCTAssertEqual(parse("guide me to city hall"), .walk(to: "city hall"))
        XCTAssertEqual(parse("stop directions"), .stopWalking)
        XCTAssertEqual(parse("what's my next turn"), .nextTurn)
        XCTAssertEqual(parse("how far", walking: true), .nextTurn)
        XCTAssertNil(parse("how far"))
        XCTAssertEqual(parse("Where am I?"), .whereAmI)
        XCTAssertEqual(parse("call my emergency contact"), .emergencyCall)
        XCTAssertEqual(parse("I need help"), .emergencyCall)
        XCTAssertEqual(parse("set my emergency contact to jordan lee"), .setEmergencyContact("Jordan Lee"))
    }

    func testHearing() {
        XCTAssertEqual(parse("start captions"), .captions(true))
        XCTAssertEqual(parse("turn on live captions"), .captions(true))
        XCTAssertEqual(parse("caption this conversation"), .captions(true))
        XCTAssertEqual(parse("captions off"), .captions(false))
        XCTAssertEqual(parse("turn on sound alerts"), .soundAlerts(true))
        XCTAssertEqual(parse("stop sound alerts"), .soundAlerts(false))
        XCTAssertEqual(parse("what did they say"), .whatWasSaid)
        XCTAssertEqual(parse("save this conversation"), .saveTranscript)
        XCTAssertEqual(parse("delete the transcript"), .clearTranscript)
    }

    func testSpeechAndMovement() {
        XCTAssertEqual(parse("speak slower"), .pace(.slow))
        XCTAssertEqual(parse("speed up"), .pace(.fast))
        XCTAssertEqual(parse("normal speed"), .pace(.normal))
        XCTAssertEqual(parse("give me more time"), .extraTime(true))
        XCTAssertEqual(parse("normal timing"), .extraTime(false))
        XCTAssertEqual(parse("What can I say?"), .help)
    }

    func testTasks() {
        XCTAssertEqual(parse("start my morning routine"), .startTask("morning"))
        XCTAssertEqual(parse("guide me through making tea step by step"), .startTask("making tea"))
        XCTAssertEqual(parse("help me do the laundry step by step"), .startTask("do the laundry"))
        XCTAssertEqual(
            parse("Teach routine make tea: fill the kettle, then turn it on, then pour the water."),
            .teachRoutine(name: "make tea", steps: ["Fill the kettle", "Turn it on", "Pour the water"])
        )
        XCTAssertEqual(
            parse("new routine called leaving home first lock the back door then take my keys"),
            .teachRoutine(name: "leaving home", steps: ["Lock the back door", "Take my keys"])
        )
        XCTAssertEqual(parse("list my routines"), .listRoutines)
        XCTAssertEqual(parse("delete the morning routine"), .deleteRoutine("morning"))
    }

    func testShortWordsDependOnWhatIsHappening() {
        XCTAssertNil(parse("next"))
        XCTAssertNil(parse("repeat"))
        XCTAssertNil(parse("stop"))
        XCTAssertEqual(parse("next", focus: .task), .taskNext)
        XCTAssertEqual(parse("Done.", focus: .task), .taskNext)
        XCTAssertEqual(parse("go back", focus: .task), .taskBack)
        XCTAssertEqual(parse("say that again", focus: .task), .taskRepeat)
        XCTAssertNil(parse("stop", focus: .task))
        XCTAssertEqual(parse("stop the task", focus: .task), .taskStop)
        XCTAssertEqual(parse("next", focus: .reading), .readMore)
        XCTAssertEqual(parse("again", focus: .reading), .readAgain)
        XCTAssertEqual(parse("stop", focus: .reading), .stopReading)
        // The full phrases work whatever is happening.
        XCTAssertEqual(parse("read more"), .readMore)
        XCTAssertEqual(parse("next step"), .taskNext)
        XCTAssertEqual(parse("stop reading"), .stopReading)
    }

    func testMemory() {
        XCTAssertEqual(parse("What was I doing?"), .whatWasIDoing)
        XCTAssertEqual(parse("where was I"), .whatWasIDoing)
        XCTAssertEqual(parse("turn on activity recall"), .recall(true))
        XCTAssertEqual(parse("forget what I was doing"), .forgetActivity)
        XCTAssertEqual(parse("when I see Sam, remind me to return his keys"), .remindWhenSeeing(person: "Sam", note: "return his keys"))
        XCTAssertEqual(parse("remind me to ask about the trip next time I see aunt maria"), .remindWhenSeeing(person: "Aunt Maria", note: "ask about the trip"))
    }

    /// These belong to features that already exist. The suite must leave them alone.
    func testOtherCommandsFallThrough() {
        for phrase in [
            "remember this", "where did I park", "read my messages", "what time is it",
            "ask Indy about the gate", "remind me to call Sam", "take a picture", "status report",
            "what medication should I take for a headache", "how much cash do I have",
            "navigate to the airport", "call Sam", "watch this", "translate to Spanish", "",
        ] {
            XCTAssertNil(parse(phrase), phrase)
        }
    }
}

final class ConfirmationTests: XCTestCase {
    func testShortAnswers() {
        for word in ["yes", "Yeah.", "yep", "okay", "do it", "go ahead", "Yes please", "that's right"] {
            XCTAssertEqual(Confirmation.parse(word), .yes, word)
        }
        for word in ["no", "Nope", "cancel", "don't", "never mind", "stop", "know"] {
            XCTAssertEqual(Confirmation.parse(word), .no, word)
        }
        XCTAssertEqual(Confirmation.parse("say that again"), .again)
        XCTAssertEqual(Confirmation.parse("what?"), .again)
    }

    func testAMixedAnswerIsNo() {
        XCTAssertEqual(Confirmation.parse("yes, no wait"), .no)
        XCTAssertEqual(Confirmation.parse("okay don't"), .no)
    }

    func testALongSentenceIsNotAnAnswer() {
        XCTAssertNil(Confirmation.parse("yes I think the weather is going to be nice tomorrow"))
        XCTAssertNil(Confirmation.parse("read this"))
        XCTAssertNil(Confirmation.parse(""))
    }

    func testAQuestionLapses() {
        let asked = Date(timeIntervalSince1970: 100)
        let pending = PendingConfirmation(action: "call", question: "Call Sam?", askedAt: asked)
        XCTAssertFalse(pending.expired(at: asked.addingTimeInterval(30)))
        XCTAssertTrue(pending.expired(at: asked.addingTimeInterval(60)))
    }
}

final class TaskGuideTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 50_000)
    private let tea = Routine(name: "Make tea", steps: ["Fill the kettle", "Turn it on", "Pour the water"])

    func testStepsFromANumberedList() {
        XCTAssertEqual(Routine.steps(from: "1. Fill the kettle 2. Turn it on 3. Pour the water"), ["Fill the kettle", "Turn it on", "Pour the water"])
        XCTAssertEqual(Routine.steps(from: "1) Open the app\n2) Tap send\n"), ["Open the app", "Tap send"])
        XCTAssertEqual(Routine.steps(from: "- wash hands\n- dry hands"), ["Wash hands", "Dry hands"])
    }

    func testStepsFromSpeech() {
        XCTAssertEqual(Routine.steps(from: "first lock the door, then take the keys and then turn off the light"), ["Lock the door", "Take the keys", "Turn off the light"])
        XCTAssertEqual(Routine.steps(from: "step one: boil water. Step two: add pasta."), ["Boil water", "Add pasta"])
        XCTAssertEqual(Routine.steps(from: "feed the cat"), ["Feed the cat"])
    }

    func testOneStepAtATime() {
        var run = TaskRun(tea, at: start)
        XCTAssertEqual(run.begin(at: start), "Make tea, 3 steps. Say next when you finish each one. Step 1 of 3. Fill the kettle.")
        XCTAssertEqual(run.next(at: start), "Step 2 of 3. Turn it on.")
        XCTAssertEqual(run.repeated(at: start), "Step 2 of 3. Turn it on.")
        XCTAssertEqual(run.back(at: start), "Step 1 of 3. Fill the kettle.")
        XCTAssertEqual(run.back(at: start), "This is the first step. Step 1 of 3. Fill the kettle.")
        _ = run.next(at: start)
        XCTAssertEqual(run.next(at: start), "Step 3 of 3. Pour the water.")
        XCTAssertEqual(run.summary, "You are doing Make tea. Step 3 of 3: Pour the water. Say next when it's done.")
        XCTAssertEqual(run.next(at: start), "That was the last step. Make tea is done.")
        XCTAssertTrue(run.finished)
        XCTAssertEqual(run.summary, "You finished Make tea.")
    }

    func testANudgeComesOnlyAfterALongQuiet() {
        var run = TaskRun(tea, at: start)
        _ = run.begin(at: start)
        XCTAssertNil(run.nudge(at: start.addingTimeInterval(100)))
        XCTAssertEqual(run.nudge(at: start.addingTimeInterval(250)), "Still on Make tea. Step 1 of 3. Fill the kettle. Say next, repeat, or stop the task.")
        XCTAssertNil(run.nudge(at: start.addingTimeInterval(300)), "the nudge itself resets the clock")
    }

    func testATaskSurvivesBeingSaved() throws {
        var run = TaskRun(tea, at: start)
        _ = run.begin(at: start)
        _ = run.next(at: start)
        let restored = try JSONDecoder().decode(TaskRun.self, from: JSONEncoder().encode(run))
        XCTAssertEqual(restored, run)
        XCTAssertEqual(restored.position, "Step 2 of 3")
    }

    func testRemindersWaitForTheirPerson() {
        var reminders = [
            PersonReminder(person: "Sam", note: "return his keys", createdAt: start),
            PersonReminder(person: "Alex", note: "ask about the trip", createdAt: start),
            PersonReminder(person: "sam", note: "say happy birthday", createdAt: start),
        ]
        XCTAssertEqual(PersonReminder.take(for: "Sam", from: &reminders), ["return his keys", "say happy birthday"])
        XCTAssertEqual(reminders.map(\.person), ["Alex"])
        XCTAssertEqual(PersonReminder.take(for: "Sam", from: &reminders), [])
    }
}

final class ActivityTrailTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 60_000)

    func testWhatIsInProgressComesFirst() {
        let entries = [
            ActivityEntry(at: now.addingTimeInterval(-1800), kind: .read, summary: "asked me to read a label"),
            ActivityEntry(at: now.addingTimeInterval(-600), kind: .task, summary: "started Make tea"),
        ]
        let answer = ActivityTrail.recall(entries: entries, inProgress: ["You are doing Make tea. Step 2 of 3: Turn it on."], enabled: true, now: now)
        XCTAssertEqual(answer, "You are doing Make tea. Step 2 of 3: Turn it on. Before that, 10 minutes ago, you started Make tea. Before that, 30 minutes ago, you asked me to read a label.")
    }

    func testWithNothingInProgressTheLatestActivityLeads() {
        let entries = [ActivityEntry(at: now.addingTimeInterval(-90), kind: .walk, summary: "started walking to the library")]
        XCTAssertEqual(ActivityTrail.recall(entries: entries, inProgress: [], enabled: true, now: now), "A minute ago, you started walking to the library.")
    }

    func testOldEntriesAreNotRecalled() {
        let entries = [ActivityEntry(at: now.addingTimeInterval(-3 * 3600), kind: .read, summary: "asked me to read a sign")]
        XCTAssertTrue(ActivityTrail.recall(entries: entries, inProgress: [], enabled: true, now: now).hasPrefix("Nothing in the last two hours."))
    }

    func testWhenRecallIsOffItSaysSoAndHowToTurnItOn() {
        let answer = ActivityTrail.recall(entries: [], inProgress: [], enabled: false, now: now)
        XCTAssertTrue(answer.contains("Activity recall is off"))
        XCTAssertTrue(answer.contains("turn on activity recall"))
    }

    func testAppendingDropsRepeatsAndOldEntries() {
        var entries = [ActivityEntry(at: now.addingTimeInterval(-30 * 3600), kind: .read, summary: "asked me to read a sign")]
        let entry = ActivityEntry(at: now, kind: .read, summary: "asked me to read a label")
        entries = ActivityTrail.appending(entry, to: entries)
        entries = ActivityTrail.appending(ActivityEntry(at: now.addingTimeInterval(5), kind: .read, summary: "asked me to read a label"), to: entries)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].at, now.addingTimeInterval(5))
    }

    func testAgo() {
        XCTAssertEqual(ActivityTrail.ago(20), "just now")
        XCTAssertEqual(ActivityTrail.ago(3 * 60), "3 minutes ago")
        XCTAssertEqual(ActivityTrail.ago(70 * 60), "about an hour ago")
        XCTAssertEqual(ActivityTrail.ago(3 * 3600), "about 3 hours ago")
    }
}

final class AccessibilitySettingsTests: XCTestCase {
    func testAnythingThatWatchesListensOrStoresStartsOff() {
        let settings = AccessibilitySettings()
        XCTAssertFalse(settings.faceRecognition)
        XCTAssertFalse(settings.soundAlerts)
        XCTAssertFalse(settings.keepTranscripts)
        XCTAssertFalse(settings.activityRecall)
        XCTAssertFalse(settings.guideSafetyAccepted)
        XCTAssertEqual(settings.patience, 1)
    }

    func testOlderSavedSettingsStillLoad() throws {
        let json = #"{"faceRecognition": true, "soundKinds": ["siren", "a_kind_from_the_future"], "pace": "slow"}"#
        let settings = try JSONDecoder().decode(AccessibilitySettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.faceRecognition)
        XCTAssertEqual(settings.soundKinds, [.siren])
        XCTAssertEqual(settings.pace, .slow)
        XCTAssertTrue(settings.guideAudioCues, "a missing field takes its default")
    }

    func testRoundTrip() throws {
        var settings = AccessibilitySettings()
        settings.names = ["Brandon"]
        settings.extraTime = true
        settings.emergencyContactNumber = "+15551234567"
        let restored = try JSONDecoder().decode(AccessibilitySettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.patience, 2.5)
    }
}
