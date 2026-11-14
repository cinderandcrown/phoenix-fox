// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The spoken commands of the workshop.
//
// Like the accessibility suite, every command is a fixed phrase matched on the phone. A
// sentence that matches nothing returns nil and goes on to the assistant as before, and a
// feature that is switched off matches nothing at all.

import Foundation

enum WorkshopCommand: Equatable, Sendable {
    // Walk-through
    case walkStart(String?)
    case walkAdd(WalkThrough.Kind, String, photo: Bool)
    case walkRead, walkFinish
    case walkSend(bot: String?)

    // Tally
    case tallyStart(String?)
    case tallyAdd(Int, String)
    case tallySet(String, Int)
    case tallyCount(String)
    case tallyRead, tallyFinish
    case tallySend(bot: String?)

    /// Takes back the last note, count, or dose, whichever came last.
    case undo

    // Ingredient watch
    case checkIngredients
    case allergyAdd(String), allergyRemove(String), allergyList

    // Dose guard
    case doseFromLabel
    case doseLog(String)
    case doseAnyway
    case doseAsk(String)
    case doseToday, doseUndo, doseErase

    // The team
    case council(String, photo: Bool)
    case relay(RelayRace.Plan)

    // Standing orders
    case orderAdd(StandingOrder.Trigger, StandingOrder.Action)
    case orderList
    case orderDelete(Int)
    case orderDeleteAll

    // Place notes
    case noteLeave(String)
    case notesHere, noteDelete

    // The day
    case closeDay(bot: String?)
    case today

    // Skills
    case skill(Skills.Match)
    case skillList

    struct Context: Equatable, Sendable {
        var settings = WorkshopSettings()
        /// The names of the wearer's assistants.
        var bots: [String] = []
        /// A walk-through is under way.
        var walking = false
        /// There is a walk-through, under way or finished, to read or send.
        var hasWalk = false
        var tallying = false
        var hasTally = false
        /// There is something the workshop just added that "undo" can take back.
        var canUndo = false
        /// Dose guard held back a dose and is waiting to hear "log it anyway".
        var doseWaiting = false
        /// The medicines already in the log.
        var medicines: [String] = []
        var skills: [Skill] = []
    }

    static func parse(_ utterance: String, context: Context) -> WorkshopCommand? {
        let said = Said(utterance)
        guard !said.isEmpty, context.settings.anyOn else { return nil }
        let settings = context.settings

        if context.canUndo, said.is(["undo", "undo that", "scratch that", "take that back", "delete the last one", "remove the last one"]) {
            return .undo
        }
        if settings.doseGuard, let command = dose(said, context) { return command }
        if settings.walkThrough, let command = walk(said, context) { return command }
        if settings.tally, let command = tally(said, context) { return command }
        if settings.ingredientWatch, let command = ingredients(said) { return command }
        if settings.placeNotes, let command = placeNotes(said) { return command }
        if settings.standingOrders, let command = orders(said, utterance, context) { return command }
        if settings.council, let command = council(said) { return command }
        if settings.closeTheDay, let command = day(said, context) { return command }
        if settings.relayRace, let plan = RelayRace.plan(utterance, bots: context.bots) { return .relay(plan) }
        if settings.skills {
            if said.is(["list my skills", "what skills do i have", "what skills are there", "read my skills"]) { return .skillList }
            if let match = Skills.match(utterance, in: context.skills) { return .skill(match) }
        }
        return nil
    }

    // MARK: - Walk-through

    private static func walk(_ said: Said, _ context: Context) -> WorkshopCommand? {
        let starts = [
            "start a walk through", "start a walkthrough", "start the walk through", "start the walkthrough",
            "start walk through", "begin a walk through", "begin a walkthrough", "new walk through", "new walkthrough",
            "start an inspection", "begin an inspection", "start a site walk",
        ]
        if let rest = said.after(starts) {
            return .walkStart(name(rest))
        }
        if context.walking {
            let photoFlags = ["photo flag", "picture flag", "flag with a photo", "flag with photo", "flag this with a photo", "flag and photo"]
            if let rest = said.after(photoFlags) { return .walkAdd(.flag, body(rest), photo: true) }
            let photoNotes = [
                "photo note", "picture note", "note with a photo", "note with photo", "take a photo note", "add a photo note",
                "add a photo", "take a photo for the walk through", "photo",
            ]
            if let rest = said.after(photoNotes) { return .walkAdd(.note, body(rest), photo: true) }
            if let rest = said.after(["flag this", "flag that", "flag it", "add a flag", "flag"]) {
                return .walkAdd(.flag, body(rest), photo: false)
            }
            if let rest = said.after(["add a note", "add note", "make a note", "note that", "note"]), !rest.isEmpty {
                return .walkAdd(.note, body(rest), photo: false)
            }
            let finishes = [
                "finish the walk through", "finish the walkthrough", "end the walk through", "end the walkthrough",
                "finish walk through", "finish the inspection", "end the inspection", "stop the walk through",
                "walk through done", "that's the walk through", "finish the site walk",
            ]
            if said.is(finishes) { return .walkFinish }
            if said.is(["read it back", "read the list", "what do i have so far", "how many items", "how many items so far"]) {
                return .walkRead
            }
        }
        guard context.hasWalk else { return nil }
        if said.is(["read the walk through", "read the walkthrough", "read back the walk through", "read the inspection"]) {
            return .walkRead
        }
        let sends = [
            "send the walk through", "send the walkthrough", "send the inspection", "send the walk through report",
            "send the inspection report", "send the report",
        ]
        if let rest = said.after(sends), let bot = recipient(rest) {
            return .walkSend(bot: bot)
        }
        return nil
    }

    // MARK: - Tally

    private static func tally(_ said: Said, _ context: Context) -> WorkshopCommand? {
        let starts = [
            "start a tally", "start a count", "start tally", "start counting", "begin a tally", "begin a count",
            "new tally", "new count", "start a stock count", "start an inventory", "start a stock take",
        ]
        if let rest = said.after(starts) {
            return .tallyStart(name(rest))
        }
        if context.tallying {
            let finishes = [
                "finish the tally", "end the tally", "finish the count", "end the count", "stop counting", "finish tally",
                "tally done", "finish counting", "done counting", "that's the count", "stop the tally", "stop the count",
            ]
            if said.is(finishes) { return .tallyFinish }
            let reads = [
                "read it back", "read the tally", "read back the tally", "read the count", "what's the count",
                "what is the count", "what's the tally", "what do i have so far", "totals", "how many items",
            ]
            if said.is(reads) { return .tallyRead }
            if let rest = said.after(["how many"]) {
                var words = rest.lowercased().split(separator: " ").map(String.init)
                for tail in [["do", "i", "have"], ["so", "far"], ["are", "there"], ["have", "i", "counted"], ["is", "that"]]
                where words.count > tail.count && Array(words.suffix(tail.count)) == tail {
                    words.removeLast(tail.count)
                }
                let item = words.joined(separator: " ")
                return item.isEmpty ? .tallyRead : .tallyCount(item)
            }
            if let rest = said.after(["set"]) {
                let words = rest.lowercased().split(separator: " ").map(String.init)
                if let split = words.lastIndex(of: "to"), split > 0,
                   let number = SpokenNumber.leading(Array(words[(split + 1)...])), split + 1 + number.used == words.count {
                    return .tallySet(words[..<split].joined(separator: " "), number.value)
                }
                return nil
            }
            if let rest = said.after(["minus", "remove", "take off", "take away", "subtract", "less"]),
               let counted = counted(rest, articles: true) {
                return .tallyAdd(-counted.count, counted.item)
            }
            if let rest = said.after(["add", "plus", "and", "another"]), let counted = counted(rest, articles: true) {
                return .tallyAdd(counted.count, counted.item)
            }
            if let counted = counted(said.text, articles: false) {
                return .tallyAdd(counted.count, counted.item)
            }
        }
        guard context.hasTally else { return nil }
        if said.is(["read the tally", "read back the tally", "read the count"]) { return .tallyRead }
        if let rest = said.after(["send the tally", "send the count", "send the stock count", "send the inventory"]),
           let bot = recipient(rest) {
            return .tallySend(bot: bot)
        }
        return nil
    }

    /// "twelve cases of cups" as a number and an item. Sentences that start with a number
    /// and are about time or arithmetic are not counts.
    private static func counted(_ text: String, articles: Bool) -> (count: Int, item: String)? {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard let number = SpokenNumber.leading(words, articles: articles), number.used < words.count else { return nil }
        var item = Array(words[number.used...])
        while let first = item.first, ["of", "more", "the"].contains(first), item.count > 1 { item.removeFirst() }
        let notItems: Set<String> = [
            "minute", "minutes", "second", "seconds", "hour", "hours", "plus", "minus", "times", "percent", "am", "pm",
            "o'clock", "divided", "and", "or", "to", "is", "are", "dollars", "degrees",
        ]
        guard let first = item.first, !notItems.contains(first), !item.contains("timer") else { return nil }
        guard item.count <= 6 else { return nil }
        return (number.value, item.joined(separator: " "))
    }

    // MARK: - Ingredient watch

    private static func ingredients(_ said: Said) -> WorkshopCommand? {
        let checks = [
            "check the ingredients", "check ingredients", "check these ingredients", "scan the ingredients",
            "check this for allergens", "check for allergens", "check the label for allergens", "check this label for allergens",
            "check for my allergies", "check this for my allergies", "ingredient check", "allergen check", "can i eat this",
            "does this have anything i'm allergic to", "is there anything i'm allergic to in this",
        ]
        if said.is(checks) { return .checkIngredients }
        if said.is(["what are my allergies", "list my allergies", "what's on my allergy list", "what am i allergic to",
                    "what ingredients are you watching for", "read my allergy list"]) {
            return .allergyList
        }
        if let rest = said.after(["i'm not allergic to", "i am not allergic to", "stop watching for"]), !rest.isEmpty {
            return .allergyRemove(rest.lowercased())
        }
        if let rest = said.after(["i'm allergic to", "i am allergic to", "watch for"]), !rest.isEmpty {
            let item = dropping(rest.lowercased(), tails: ["in ingredients", "in the ingredients", "on labels"])
            return item.isEmpty ? nil : .allergyAdd(item)
        }
        let lists = ["my allergies", "my allergy list", "my ingredient list", "my allergens"]
        if let rest = said.after(["add"]) {
            for list in lists {
                let item = dropping(rest.lowercased(), tails: ["to " + list])
                if item != rest.lowercased(), !item.isEmpty { return .allergyAdd(item) }
            }
        }
        if let rest = said.after(["remove", "take", "delete"]) {
            for list in lists {
                let item = dropping(rest.lowercased(), tails: ["from " + list, "off " + list])
                if item != rest.lowercased(), !item.isEmpty { return .allergyRemove(item) }
            }
        }
        return nil
    }

    // MARK: - Dose guard

    private static func dose(_ said: Said, _ context: Context) -> WorkshopCommand? {
        if context.doseWaiting, said.is(["log it anyway", "log anyway", "i did take it", "log it", "i took it"]) {
            return .doseAnyway
        }
        let fromLabel = [
            "i'm taking this", "i am taking this", "i'm taking this pill", "i'm taking this medicine",
            "i'm taking this medication", "i took this", "i just took this", "i took this pill", "i took this medicine",
            "log this medicine", "log this medication", "log this pill", "log this dose",
        ]
        if said.is(fromLabel) { return .doseFromLabel }
        if said.is(["undo that dose", "undo the dose", "undo the last dose", "delete the last dose", "remove the last dose"]) {
            return .doseUndo
        }
        if said.is(["erase my dose log", "erase my medicine log", "delete my dose log", "delete my medicine log",
                    "clear my dose log", "clear my medicine log"]) {
            return .doseErase
        }
        if said.is(["what have i taken today", "what did i take today", "what medicine have i taken",
                    "what medicine have i taken today", "what medication have i taken today", "read my dose log",
                    "read my medicine log"]) {
            return .doseToday
        }
        if let rest = said.after(["log a dose of", "log my dose of", "record a dose of"]), !rest.isEmpty {
            return .doseLog(rest)
        }
        // "I took my …" starts many sentences that are not about medicine, so it counts
        // only for a medicine that is already in the log.
        let took = ["i took my", "i just took my", "i've taken my", "i have taken my", "i'm taking my", "i am taking my",
                    "i took the", "i just took the", "i took", "i just took"]
        if let rest = said.after(took), let known = known(rest, context) {
            return .doseLog(known)
        }
        let asks = [
            "did i take my", "did i take the", "did i take", "have i taken my", "have i taken the", "have i taken",
            "when did i last take my", "when did i last take the", "when did i last take", "when did i take my",
            "when did i take the", "when did i take",
        ]
        if let rest = said.after(asks) {
            let name = dropping(rest.lowercased(), tails: ["today", "yet", "already", "this morning", "tonight", "yet today"])
            if ["medicine", "medication", "meds", "pills", "pill", "tablets", "anything"].contains(name) { return .doseToday }
            if let known = known(name, context) { return .doseAsk(known) }
        }
        return nil
    }

    private static func known(_ name: String, _ context: Context) -> String? {
        guard !name.isEmpty, name.split(separator: " ").count <= 5 else { return nil }
        return context.medicines.first { DoseLog.matches($0, name) }
    }

    // MARK: - Place notes

    private static func placeNotes(_ said: Said) -> WorkshopCommand? {
        let leaves = [
            "leave a note here", "leave a note for this place", "leave a note at this spot", "pin a note here",
            "leave a place note", "drop a note here", "note for this place", "leave a note for here",
        ]
        if let rest = said.after(leaves) {
            return .noteLeave(body(rest))
        }
        if said.is(["any notes here", "are there any notes here", "what notes are here", "read the notes here", "notes here",
                    "what did i leave here", "any notes for this place", "do i have notes here", "is there a note here",
                    "do i have any notes here"]) {
            return .notesHere
        }
        if said.is(["delete the note here", "delete that note", "remove the note here", "delete this note", "remove that note"]) {
            return .noteDelete
        }
        return nil
    }

    // MARK: - Standing orders

    private static func orders(_ said: Said, _ utterance: String, _ context: Context) -> WorkshopCommand? {
        if said.is(["list my standing orders", "what are my standing orders", "read my standing orders", "standing orders"]) {
            return .orderList
        }
        if said.is(["delete all standing orders", "cancel all standing orders", "remove all standing orders",
                    "clear my standing orders", "delete all my standing orders"]) {
            return .orderDeleteAll
        }
        let deletes = ["delete standing order number", "delete standing order", "cancel standing order number",
                       "cancel standing order", "remove standing order number", "remove standing order"]
        if let rest = said.after(deletes), let number = SpokenNumber.value(rest), number > 0 {
            return .orderDelete(number)
        }
        if let order = StandingOrders.parse(utterance, bots: context.bots) {
            return .orderAdd(order.trigger, order.action)
        }
        return nil
    }

    // MARK: - Council and the day

    private static func council(_ said: Said) -> WorkshopCommand? {
        let leads = [
            "ask the council", "put it to the council", "council vote", "take a vote", "ask everyone to vote",
            "ask the team to vote", "poll the team", "poll the council", "poll everyone",
        ]
        guard let rest = said.after(leads) else { return nil }
        var words = rest.split(separator: " ").map(String.init)
        while let first = words.first?.lowercased(), ["on", "about", "to", "vote"].contains(first) { words.removeFirst() }
        guard words.count >= 2 else { return nil }
        let lower = " " + words.joined(separator: " ").lowercased() + " "
        let photo = [" this ", " these ", " those ", " looking at ", " in front of me "].contains(where: lower.contains)
        return .council(WorkshopText.sentence(words.joined(separator: " ")), photo: photo)
    }

    private static func day(_ said: Said, _ context: Context) -> WorkshopCommand? {
        if said.is(["what did i do today", "what have i done today", "read today's log", "read my day"]) {
            return .today
        }
        let closes = ["close the day", "close out the day", "close my day", "close out my day", "end of day report",
                      "wrap up the day", "wrap up my day"]
        guard let rest = said.after(closes), let bot = recipient(rest) else { return nil }
        return .closeDay(bot: bot)
    }

    // MARK: - Shared

    /// The assistant named after a command: "to Rally", "with Indy", or nothing, which
    /// means the default assistant. The outer nil means what follows is not a name at
    /// all, so the sentence is not a workshop command.
    private static func recipient(_ rest: String) -> String?? {
        if rest.isEmpty { return .some(nil) }
        for lead in ["to ", "with ", "and send it to ", "and send to ", "over to "] where rest.lowercased().hasPrefix(lead) {
            let name = String(rest.dropFirst(lead.count))
            guard !name.isEmpty, name.split(separator: " ").count <= 4 else { return nil }
            return .some(name)
        }
        return nil
    }

    /// The name given to a walk-through or a tally: "of the Elm Street house" is "Elm Street house".
    private static func name(_ rest: String) -> String? {
        var words = rest.split(separator: " ").map(String.init)
        while let first = words.first?.lowercased(), ["of", "at", "for", "called", "named", "the", "in", "on"].contains(first) {
            words.removeFirst()
        }
        guard !words.isEmpty else { return nil }
        return String(words.joined(separator: " ").prefix(60))
    }

    /// What follows "note" or "leave a note here", without the joining word.
    private static func body(_ rest: String) -> String {
        var words = rest.split(separator: " ").map(String.init)
        if words.count >= 2, words[0].lowercased() == "that", words[1].lowercased() == "says" { words.removeFirst(2) }
        if let first = words.first?.lowercased(), ["saying", "that"].contains(first), words.count > 1 { words.removeFirst() }
        return words.joined(separator: " ")
    }

    private static func dropping(_ text: String, tails: [String]) -> String {
        for tail in tails.sorted(by: { $0.count > $1.count }) {
            if text == tail { return "" }
            if text.hasSuffix(" " + tail) { return String(text.dropLast(tail.count + 1)) }
        }
        return text
    }
}
