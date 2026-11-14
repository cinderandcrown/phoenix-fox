// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import XCTest
@testable import PhoenixFox

final class WorkshopCommandTests: XCTestCase {
    private func context(_ change: (inout WorkshopCommand.Context) -> Void = { _ in }) -> WorkshopCommand.Context {
        var context = WorkshopCommand.Context()
        OwnerProfile.apply(to: &context.settings)
        context.bots = ["Fire Fox", "Indy", "Driver", "Rally"]
        change(&context)
        return context
    }

    private func parse(_ text: String, _ change: (inout WorkshopCommand.Context) -> Void = { _ in }) -> WorkshopCommand? {
        WorkshopCommand.parse(text, context: context(change))
    }

    // MARK: - Switches

    func testNothingMatchesWhenEverythingIsOff() {
        let off = WorkshopCommand.Context()
        for sentence in ["start a tally", "check the ingredients", "ask the council should I buy this", "close the day",
                         "leave a note here the key is under the mat", "I'm taking this"] {
            XCTAssertNil(WorkshopCommand.parse(sentence, context: off), sentence)
        }
    }

    func testAFeatureThatIsOffDoesNotMatch() {
        XCTAssertNil(parse("start a tally") { $0.settings.tally = false })
        XCTAssertNil(parse("check the ingredients") { $0.settings.ingredientWatch = false })
        XCTAssertNil(parse("I'm taking this") { $0.settings.doseGuard = false })
        XCTAssertNil(parse("ask the council should I buy this") { $0.settings.council = false })
        XCTAssertNil(parse("ask Indy to find it then have Driver book it") { $0.settings.relayRace = false })
        XCTAssertNil(parse("whenever I put my glasses on say hello") { $0.settings.standingOrders = false })
        XCTAssertNil(parse("any notes here") { $0.settings.placeNotes = false })
        XCTAssertNil(parse("close the day") { $0.settings.closeTheDay = false })
        XCTAssertNil(parse("start a walk through") { $0.settings.walkThrough = false })
        XCTAssertNil(parse("list my skills") { $0.settings.skills = false })
    }

    // MARK: - What must still reach the assistant

    func testOrdinarySentencesAreLeftAlone() {
        let sentences = [
            "what's the weather tomorrow", "ask Indy to find three caterers", "set a timer for ten minutes",
            "remind me to call Dana", "take a photo", "note to self buy milk", "flag", "two plus two",
            "I took the bus this morning", "did I take the trash out", "when is my next meeting",
            "send the report to Rally", "read it back", "undo", "stop", "how many days until Friday",
            "add milk to my shopping list", "what is this", "12 minutes", "log it",
        ]
        for sentence in sentences {
            XCTAssertNil(parse(sentence), sentence)
        }
    }

    func testWhileCountingOrdinarySentencesStillPass() {
        for sentence in ["set a timer for ten minutes", "what time is it", "ten minute timer", "5 plus 5", "2 pm", "stop",
                         "ask Indy to check the price of cups", "remove peanuts from my shopping list"] {
            XCTAssertNil(parse(sentence) { $0.tallying = true; $0.hasTally = true }, sentence)
        }
    }

    // MARK: - Walk-through

    func testAWalkThroughIsStartedWithOrWithoutAName() {
        XCTAssertEqual(parse("Jarvis, start a walk-through of the Elm Street house"), .walkStart("Elm Street house"))
        XCTAssertEqual(parse("start a walkthrough"), .walkStart(nil))
        XCTAssertEqual(parse("begin an inspection at Unit 4B"), .walkStart("Unit 4B"))
    }

    func testNotesFlagsAndPhotosOnlyDuringAWalkThrough() {
        XCTAssertNil(parse("note the door sticks"))
        XCTAssertNil(parse("photo note the crack"))
        let walking: (inout WorkshopCommand.Context) -> Void = { $0.walking = true; $0.hasWalk = true }
        XCTAssertEqual(parse("note the door sticks", walking), .walkAdd(.note, "the door sticks", photo: false))
        XCTAssertEqual(parse("Note that Dana wants a quote", walking), .walkAdd(.note, "Dana wants a quote", photo: false))
        XCTAssertEqual(parse("flag the outlet has no cover", walking), .walkAdd(.flag, "the outlet has no cover", photo: false))
        XCTAssertEqual(parse("flag this", walking), .walkAdd(.flag, "", photo: false))
        XCTAssertEqual(parse("photo note water stain on the ceiling", walking), .walkAdd(.note, "water stain on the ceiling", photo: true))
        XCTAssertEqual(parse("photo flag cracked tile", walking), .walkAdd(.flag, "cracked tile", photo: true))
        XCTAssertEqual(parse("photo", walking), .walkAdd(.note, "", photo: true))
        XCTAssertEqual(parse("read it back", walking), .walkRead)
        XCTAssertEqual(parse("finish the walk-through", walking), .walkFinish)
        // The general "take a photo" is not the walk-through's.
        XCTAssertNil(parse("take a photo", walking))
        XCTAssertNil(parse("note", walking))
    }

    func testAFinishedWalkThroughCanBeReadAndSent() {
        let finished: (inout WorkshopCommand.Context) -> Void = { $0.hasWalk = true }
        XCTAssertEqual(parse("send the walk-through to Rally", finished), .walkSend(bot: "Rally"))
        XCTAssertEqual(parse("send the report", finished), .walkSend(bot: nil))
        XCTAssertEqual(parse("read the walkthrough", finished), .walkRead)
        XCTAssertNil(parse("send the report card to school on Monday morning please", finished))
    }

    // MARK: - Tally

    func testATallyIsStarted() {
        XCTAssertEqual(parse("start a tally of the stockroom"), .tallyStart("stockroom"))
        XCTAssertEqual(parse("start counting"), .tallyStart(nil))
    }

    func testCountsAreAddedAndTakenAway() {
        XCTAssertNil(parse("twelve cases of cups"))
        let counting: (inout WorkshopCommand.Context) -> Void = { $0.tallying = true; $0.hasTally = true }
        XCTAssertEqual(parse("twelve cases of cups", counting), .tallyAdd(12, "cases of cups"))
        XCTAssertEqual(parse("40 lids", counting), .tallyAdd(40, "lids"))
        XCTAssertEqual(parse("add a box of straws", counting), .tallyAdd(1, "box of straws"))
        XCTAssertEqual(parse("plus two dozen eggs", counting), .tallyAdd(24, "eggs"))
        XCTAssertEqual(parse("another three of the lids", counting), .tallyAdd(3, "lids"))
        XCTAssertEqual(parse("minus two lids", counting), .tallyAdd(-2, "lids"))
        XCTAssertEqual(parse("take off a case of cups", counting), .tallyAdd(-1, "case of cups"))
        XCTAssertEqual(parse("set lids to thirty five", counting), .tallySet("lids", 35))
        XCTAssertEqual(parse("how many lids", counting), .tallyCount("lids"))
        XCTAssertEqual(parse("how many lids do I have", counting), .tallyCount("lids"))
        XCTAssertEqual(parse("what's the count", counting), .tallyRead)
        XCTAssertEqual(parse("stop counting", counting), .tallyFinish)
    }

    func testAFinishedTallyCanBeReadAndSent() {
        let finished: (inout WorkshopCommand.Context) -> Void = { $0.hasTally = true }
        XCTAssertEqual(parse("send the tally to Rally", finished), .tallySend(bot: "Rally"))
        XCTAssertEqual(parse("read the tally", finished), .tallyRead)
        XCTAssertNil(parse("twelve cups", finished))
    }

    func testUndoOnlyWhenThereIsSomethingToUndo() {
        XCTAssertNil(parse("undo that"))
        XCTAssertEqual(parse("undo that") { $0.canUndo = true }, .undo)
        XCTAssertEqual(parse("scratch that") { $0.canUndo = true }, .undo)
    }

    // MARK: - Ingredient watch

    func testIngredientCommands() {
        XCTAssertEqual(parse("Jarvis, check the ingredients"), .checkIngredients)
        XCTAssertEqual(parse("can I eat this?"), .checkIngredients)
        XCTAssertEqual(parse("add peanuts to my allergies"), .allergyAdd("peanuts"))
        XCTAssertEqual(parse("I'm allergic to tree nuts"), .allergyAdd("tree nuts"))
        XCTAssertEqual(parse("remove dairy from my allergy list"), .allergyRemove("dairy"))
        XCTAssertEqual(parse("I'm not allergic to soy"), .allergyRemove("soy"))
        XCTAssertEqual(parse("what are my allergies"), .allergyList)
    }

    // MARK: - Dose guard

    func testDoseCommands() {
        XCTAssertEqual(parse("I'm taking this"), .doseFromLabel)
        XCTAssertEqual(parse("log a dose of Vitamin D"), .doseLog("Vitamin D"))
        XCTAssertEqual(parse("what have I taken today"), .doseToday)
        XCTAssertEqual(parse("did I take my meds today"), .doseToday)
        XCTAssertEqual(parse("undo that dose"), .doseUndo)
        XCTAssertEqual(parse("erase my medicine log"), .doseErase)
    }

    func testANameIsOnlyAMedicineWhenItIsInTheLog() {
        XCTAssertNil(parse("I took my dog for a walk"))
        XCTAssertNil(parse("did I take my keys"))
        let known: (inout WorkshopCommand.Context) -> Void = { $0.medicines = ["Ibuprofen Tablets 200 mg", "Lisinopril 10 mg"] }
        XCTAssertEqual(parse("I took my ibuprofen", known), .doseLog("Ibuprofen Tablets 200 mg"))
        XCTAssertEqual(parse("did I take my lisinopril yet", known), .doseAsk("Lisinopril 10 mg"))
        XCTAssertEqual(parse("when did I last take ibuprofen", known), .doseAsk("Ibuprofen Tablets 200 mg"))
        XCTAssertNil(parse("I took my dog for a walk", known))
    }

    func testLogItAnywayOnlyAfterAWarning() {
        XCTAssertNil(parse("log it anyway"))
        XCTAssertEqual(parse("log it anyway") { $0.doseWaiting = true }, .doseAnyway)
    }

    // MARK: - The team

    func testCouncil() {
        XCTAssertEqual(parse("ask the council should I buy this drill"), .council("Should I buy this drill", photo: true))
        XCTAssertEqual(parse("take a vote on whether we move the launch to Friday"), .council("Whether we move the launch to Friday", photo: false))
        XCTAssertEqual(parse("put it to the council: is Dana right about the budget?"), .council("Is Dana right about the budget", photo: false))
        XCTAssertNil(parse("ask the council"))
        XCTAssertNil(parse("council tax is due when"))
    }

    func testRelayRace() {
        guard case .relay(let plan)? = parse("ask Indy to find three caterers, then have Driver book the cheapest") else {
            return XCTFail("expected a relay")
        }
        XCTAssertEqual(plan.steps.map(\.bot), ["Indy", "Driver"])
    }

    func testStandingOrders() {
        XCTAssertEqual(parse("whenever I put my glasses on, ask Fire Fox for my brief"),
                       .orderAdd(.putOn, .ask(bot: "Fire Fox", text: "Give me my brief")))
        XCTAssertEqual(parse("list my standing orders"), .orderList)
        XCTAssertEqual(parse("delete standing order two"), .orderDelete(2))
        XCTAssertEqual(parse("cancel standing order number 3"), .orderDelete(3))
        XCTAssertEqual(parse("delete all standing orders"), .orderDeleteAll)
        XCTAssertNil(parse("delete standing order zero"))
    }

    func testAnOrderAboutAnAssistantIsNotARelayRace() {
        // "then" is not in it, so it is one order, and the order is found before the relay is tried.
        XCTAssertEqual(parse("every day at 8 am ask Indy for the news"), .orderAdd(.timeOfDay(480), .ask(bot: "Indy", text: "Give me the news")))
    }

    // MARK: - Place notes and the day

    func testPlaceNotes() {
        XCTAssertEqual(parse("leave a note here: breaker 14 is the kitchen"), .noteLeave("breaker 14 is the kitchen"))
        XCTAssertEqual(parse("leave a note here saying Dana has the spare key"), .noteLeave("Dana has the spare key"))
        XCTAssertEqual(parse("leave a note here"), .noteLeave(""))
        XCTAssertEqual(parse("any notes here?"), .notesHere)
        XCTAssertEqual(parse("delete that note"), .noteDelete)
    }

    func testTheDay() {
        XCTAssertEqual(parse("close the day"), .closeDay(bot: nil))
        XCTAssertEqual(parse("close out the day with Rally"), .closeDay(bot: "Rally"))
        XCTAssertEqual(parse("what did I do today"), .today)
        XCTAssertNil(parse("close the day care account"))
    }

    // MARK: - Skills

    func testSkillsComeLastSoTheyCannotTakeABuiltInCommand() throws {
        let thief = Skill(id: "thief", name: "Thief", phrases: ["check the ingredients", "close the day"], ask: "Hello")
        let price = Skills.examples[0]
        let installed: (inout WorkshopCommand.Context) -> Void = { $0.skills = [thief, price] }
        XCTAssertEqual(parse("check the ingredients", installed), .checkIngredients)
        XCTAssertEqual(parse("price check", installed), .skill(Skills.Match(skill: price, slot: nil)))
        XCTAssertEqual(parse("list my skills", installed), .skillList)
    }

    func testHealthCommandsAreMarkedSoTheyStayOutOfTheHistory() {
        XCTAssertTrue(WorkshopCommand.checkIngredients.isHealth)
        XCTAssertTrue(WorkshopCommand.doseLog("ibuprofen").isHealth)
        XCTAssertTrue(WorkshopCommand.doseAnyway.isHealth)
        XCTAssertTrue(WorkshopCommand.allergyAdd("peanuts").isHealth)
        XCTAssertFalse(WorkshopCommand.tallyRead.isHealth)
        XCTAssertFalse(WorkshopCommand.undo.isHealth)
    }
}
