// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Joins the workshop's cores to the glasses, the phone, and the relay.
//
// The cores in Core/ decide everything: what a sentence means, what a label says, whether
// a dose is too soon, how a council voted. This file only fetches what they need (a
// picture, a position, an assistant's reply), keeps their records sealed on the phone,
// and hands back the line to say.
//
// Nothing here turns the camera on by itself. A picture is taken only inside a command
// the wearer spoke, or a skill they added and then started, and the capture light is on
// whenever it is.

import Combine
import Foundation

@MainActor
final class WorkshopCoordinator: ObservableObject {
    static let shared = WorkshopCoordinator()

    typealias Snapshot = () async -> Data?
    /// Says a short line while a longer piece of work goes on.
    typealias Progress = (String) -> Void

    /// Every walk-through kept, oldest first. The last one may still be under way.
    @Published private(set) var walks: [WalkThrough]
    /// The count under way, or the last one finished.
    @Published private(set) var tally: Tally?
    @Published private(set) var orders: [StandingOrder]
    @Published private(set) var skills: [Skill]
    @Published private(set) var doses: DoseLog
    @Published private(set) var notes: PlaceNotes
    /// What Ingredient watch looks for.
    @Published private(set) var watchList: WatchList
    private var journal: WorkshopJournal

    private enum Undoable { case walk, tally, dose }
    private var lastAdded: Undoable?
    private var heldDose: (name: String, gapHours: Double?, source: Dose.Source, at: Date)?
    private var lastReadNote: UUID?
    private var watchers: Set<AnyCancellable> = []
    private var clock: Task<Void, Never>?

    static let walksKept = 10

    private init() {
        walks = AccessStore.load([WalkThrough].self, from: Self.walksFile) ?? []
        tally = AccessStore.load(Tally.self, from: Self.tallyFile)
        orders = AccessStore.load([StandingOrder].self, from: Self.ordersFile) ?? []
        skills = AccessStore.load([Skill].self, from: Self.skillsFile) ?? []
        doses = AccessStore.load(DoseLog.self, from: Self.dosesFile) ?? DoseLog()
        notes = AccessStore.load(PlaceNotes.self, from: Self.notesFile) ?? PlaceNotes()
        journal = AccessStore.load(WorkshopJournal.self, from: Self.journalFile) ?? WorkshopJournal()
        watchList = AccessStore.load(WatchList.self, from: Self.watchFile) ?? WatchList()
    }

    private static let walksFile = "workshop-walks"
    private static let tallyFile = "workshop-tally"
    private static let ordersFile = "workshop-orders"
    private static let skillsFile = "workshop-skills"
    private static let dosesFile = "workshop-doses"
    private static let notesFile = "workshop-notes"
    private static let journalFile = "workshop-journal"
    private static let watchFile = "workshop-ingredients"

    private var settings: WorkshopSettings { SettingsManager.shared.workshop }
    private var bots: [AssistantBot] { AssistantRoster.normalized(SettingsManager.shared.settings.assistantBots) }
    private var calendar: Calendar { .current }

    private var activeWalk: WalkThrough? {
        guard let last = walks.last, last.finishedAt == nil else { return nil }
        return last
    }

    private var activeTally: Tally? {
        guard let tally, tally.finishedAt == nil else { return nil }
        return tally
    }

    // MARK: - The turn

    struct Reply: Equatable, Sendable {
        var text: String
        /// True when the turn was about the wearer's health and belongs in no history.
        var offRecord: Bool
    }

    /// Handles one sentence. Returns the line to say, or nil when the sentence is not for
    /// the workshop.
    func handle(_ text: String, snapshot: @escaping Snapshot, progress: @escaping Progress) async -> Reply? {
        let settings = self.settings
        guard settings.anyOn else { return nil }
        if let held = heldDose, Date().timeIntervalSince(held.at) > 120 { heldDose = nil }

        let context = WorkshopCommand.Context(
            settings: settings,
            bots: bots.map(\.name),
            walking: activeWalk != nil,
            hasWalk: !walks.isEmpty,
            tallying: activeTally != nil,
            hasTally: tally != nil,
            canUndo: lastAdded != nil,
            doseWaiting: heldDose != nil,
            medicines: doses.names,
            skills: skills
        )
        guard let command = WorkshopCommand.parse(text, context: context) else { return nil }
        if command != .doseAnyway { heldDose = nil }
        // "Undo" right after a dose is about the dose.
        let offRecord = command.isHealth || (command == .undo && lastAdded == .dose)
        let line = await perform(command, snapshot: snapshot, progress: progress)
        return Reply(text: line, offRecord: offRecord)
    }

    private func perform(_ command: WorkshopCommand, snapshot: @escaping Snapshot, progress: @escaping Progress) async -> String {
        switch command {
        case .walkStart(let name): return startWalk(name)
        case .walkAdd(let kind, let text, let photo): return await addToWalk(kind, text, photo: photo, snapshot: snapshot)
        case .walkRead: return walks.last?.spokenSummary() ?? Self.noWalk
        case .walkFinish: return finishWalk()
        case .walkSend(let bot): return await sendWalk(to: bot)

        case .tallyStart(let name): return startTally(name)
        case .tallyAdd(let count, let item): return changeTally { $0.add(count, of: item) }
        case .tallySet(let item, let count): return changeTally { $0.set(count, of: item) }
        case .tallyCount(let item):
            guard let line = tally?.count(of: item) else { return "\(WorkshopText.sentence(item)) is not on the tally." }
            return Tally.spoken(line)
        case .tallyRead: return tally?.spokenSummary() ?? Self.noTally
        case .tallyFinish: return finishTally()
        case .tallySend(let bot): return await sendTally(to: bot)

        case .undo: return undo()

        case .checkIngredients: return await checkIngredients(snapshot: snapshot, progress: progress)
        case .allergyAdd(let item): return watch(item)
        case .allergyRemove(let item): return unwatch(item)
        case .allergyList:
            let watching = watchList.names
            return watching.isEmpty
                ? "Your ingredient list is empty. Say, for example, \"add peanuts to my allergies\"."
                : "I look for: \(WorkshopText.list(watching))."

        case .doseFromLabel: return await doseFromLabel(snapshot: snapshot, progress: progress)
        case .doseLog(let name): return logDose(name, gapHours: nil, source: .spoken, force: false)
        case .doseAnyway:
            guard let held = heldDose else { return "There is no dose waiting." }
            heldDose = nil
            return logDose(held.name, gapHours: held.gapHours, source: held.source, force: true)
        case .doseAsk(let name):
            return DoseGuard.spokenLast(of: name, in: doses, now: Date(), calendar: calendar)
        case .doseToday: return DoseGuard.spokenToday(doses, now: Date(), calendar: calendar)
        case .doseUndo: return undoDose()
        case .doseErase:
            eraseDoses()
            return "The medicine log is erased."

        case .council(let question, let photo): return await council(question, photo: photo, snapshot: snapshot)
        case .relay(let plan): return await run(plan, progress: progress)

        case .orderAdd(let trigger, let action): return addOrder(trigger, action)
        case .orderList: return spokenOrders()
        case .orderDelete(let number):
            guard orders.indices.contains(number - 1) else { return "There is no standing order \(number)." }
            let removed = orders.remove(at: number - 1)
            saveOrders()
            return "Deleted: \(removed.summary)."
        case .orderDeleteAll:
            orders.removeAll()
            saveOrders()
            return "All standing orders are deleted."

        case .noteLeave(let text): return await leaveNote(text)
        case .notesHere: return await notesHere()
        case .noteDelete: return await deleteNote()

        case .closeDay(let bot): return await closeDay(with: bot)
        case .today: return DaySheet.spoken(journal.entries(on: Date(), calendar: calendar))

        case .skill(let match): return await run(match, snapshot: snapshot)
        case .skillList:
            guard !skills.isEmpty else { return "You have no skills. Add one in Settings, under Workshop." }
            let lines = skills.map { skill in
                "\(skill.name): say \"\(skill.phrases.first.map(Self.sayable) ?? "")\""
            }
            return "\(WorkshopText.count(skills.count, "skill")). \(lines.joined(separator: ". "))."
        }
    }

    /// A phrase without its slot, for saying aloud.
    private static func sayable(_ phrase: String) -> String {
        guard let open = phrase.firstIndex(of: "{") else { return phrase }
        return phrase[..<open].trimmingCharacters(in: .whitespaces) + ", then what you want"
    }

    // MARK: - Walk-through

    private func startWalk(_ name: String?) -> String {
        if let open = activeWalk {
            return "The \(open.name) walk-through is still open, with \(open.spokenCounts). Say \"finish the walk-through\" first."
        }
        let now = Date()
        let title = name ?? WorkshopText.stamp(now, date: .medium, time: .none, calendar: calendar, locale: .current)
        walks.append(WalkThrough(name: title, startedAt: now))
        while walks.count > Self.walksKept {
            let dropped = walks.removeFirst()
            dropped.photos.forEach(AccessStore.remove)
        }
        saveWalks()
        return "Walk-through started: \(title). Say note, flag, or photo note as you go. Say \"finish the walk-through\" when you are done."
    }

    private func addToWalk(_ kind: WalkThrough.Kind, _ text: String, photo: Bool, snapshot: Snapshot) async -> String {
        guard let index = walks.indices.last, walks[index].finishedAt == nil else { return Self.noWalk }
        guard !walks[index].isFull else {
            return "This walk-through is full at \(WalkThrough.itemLimit) items. Finish it and start another."
        }
        let id = UUID()
        var photoName: String?
        var missed = false
        if photo {
            if let jpeg = await picture(snapshot), AccessStore.save(jpeg, to: Self.photoFile(id)) {
                photoName = Self.photoFile(id)
            } else {
                missed = true
            }
        }
        // The walk-through may have been finished while the picture was being taken.
        guard walks.indices.contains(index), walks[index].finishedAt == nil,
              let item = walks[index].add(kind, text, photo: photoName, id: id, at: Date()) else {
            if let photoName { AccessStore.remove(photoName) }
            return Self.noWalk
        }
        saveWalks()
        lastAdded = .walk
        let ack = walks[index].spokenAck(for: item)
        return missed ? "I couldn't take the picture. \(ack.dropLast()), without a photo." : ack
    }

    private func finishWalk() -> String {
        guard let index = walks.indices.last, walks[index].finishedAt == nil else { return Self.noWalk }
        walks[index].finishedAt = Date()
        saveWalks()
        lastAdded = nil
        let walk = walks[index]
        note(.walkThrough, "\(walk.name): \(walk.spokenCounts)")
        return "Walk-through finished: \(walk.spokenCounts). To file it, say \"send the walk-through to\" and an assistant's name. It is also in Settings, under Workshop."
    }

    private func sendWalk(to spoken: String?) async -> String {
        guard let walk = walks.last else { return Self.noWalk }
        guard walk.finishedAt != nil else { return "The walk-through is still open. Say \"finish the walk-through\" first." }
        guard let bot = resolve(spoken) else { return unknownBot(spoken) }
        let sending = walk.photosToSend()
        let pictures = sending.compactMap { $0.photo.flatMap(photo(named:)) }
        // A picture that could not be read back is not numbered in the report.
        let sent = pictures.count == sending.count ? sending : []
        let report = walk.report(sent: sent, calendar: calendar, limit: WalkThrough.reportLimit)
        let request = """
        This is a walk-through report from my glasses\(sent.isEmpty ? "" : ", with its photos in the order they are numbered"). File it. Then tell me in two sentences what needs attention first.

        \(report)
        """
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: request, cleaned: request, images: sent.isEmpty ? [] : pictures, intent: "walkthrough", targetBot: bot.name
            )
            let answer = Self.joined(replies)
            TaskLog.append(bot: bot.name, request: "Walk-through: \(walk.name)", result: answer)
            var line = "Sent to \(bot.name)"
            let kept = walk.photos.count - sent.count
            if !sent.isEmpty { line += " with \(WorkshopText.count(sent.count, "photo"))" }
            if kept > 0 { line += ". \(WorkshopText.count(kept, "more photo")) stayed on the phone" }
            return answer.isEmpty ? line + "." : "\(line). \(bot.name) says: \(answer)"
        } catch {
            return Self.failure(error)
        }
    }

    /// The report of a walk-through with every photo numbered, for sharing from Settings.
    func report(for walk: WalkThrough) -> String {
        walk.report(calendar: calendar)
    }

    func photo(named name: String) -> Data? {
        AccessStore.load(Data.self, from: name)
    }

    func removeWalk(_ id: UUID) {
        guard let index = walks.firstIndex(where: { $0.id == id }) else { return }
        walks.remove(at: index).photos.forEach(AccessStore.remove)
        saveWalks()
    }

    private static func photoFile(_ id: UUID) -> String { "workshop-photo-\(id.uuidString)" }

    private func saveWalks() {
        AccessStore.save(walks, to: Self.walksFile)
    }

    // MARK: - Tally

    private func startTally(_ name: String?) -> String {
        if let open = activeTally {
            return "The \(open.name) tally is still open. Say \"finish the tally\" first."
        }
        let now = Date()
        let title = name ?? WorkshopText.stamp(now, date: .medium, time: .none, calendar: calendar, locale: .current)
        tally = Tally(name: title, startedAt: now)
        saveTally()
        return "Tally started: \(title). Say a number and an item, like \"twelve cases of cups\". Say \"finish the tally\" when you are done."
    }

    private func changeTally(_ change: (inout Tally) -> Tally.Line?) -> String {
        guard var open = activeTally else { return Self.noTally }
        guard let line = change(&open) else {
            return "The tally is full at \(Tally.itemLimit) items. Finish it and start another."
        }
        tally = open
        saveTally()
        lastAdded = .tally
        return Tally.spoken(line)
    }

    private func finishTally() -> String {
        guard var open = activeTally else { return Self.noTally }
        open.finishedAt = Date()
        tally = open
        saveTally()
        lastAdded = nil
        note(.tally, "\(open.name): \(WorkshopText.count(open.lines.count, "item")), \(open.total) in all")
        return "Tally finished. \(open.spokenSummary()) To file it, say \"send the tally to\" and an assistant's name."
    }

    private func sendTally(to spoken: String?) async -> String {
        guard let tally else { return Self.noTally }
        guard !tally.isEmpty else { return "The tally is empty." }
        guard let bot = resolve(spoken) else { return unknownBot(spoken) }
        let request = """
        This is a count taken by voice through my glasses, as CSV. File it and reply in one sentence.

        Name: \(tally.name)

        \(Self.fitted(tally.csv(), limit: 6_500))
        """
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: request, cleaned: request, images: [], intent: "tally", targetBot: bot.name
            )
            let answer = Self.joined(replies)
            TaskLog.append(bot: bot.name, request: "Tally: \(tally.name)", result: answer)
            return answer.isEmpty ? "Sent to \(bot.name)." : "Sent to \(bot.name). \(bot.name) says: \(answer)"
        } catch {
            return Self.failure(error)
        }
    }

    private func saveTally() {
        if let tally {
            AccessStore.save(tally, to: Self.tallyFile)
        } else {
            AccessStore.remove(Self.tallyFile)
        }
    }

    // MARK: - Undo

    private func undo() -> String {
        defer { lastAdded = nil }
        switch lastAdded {
        case .walk:
            guard let index = walks.indices.last, let removed = walks[index].removeLast() else { return "There is nothing to undo." }
            if let photo = removed.photo { AccessStore.remove(photo) }
            saveWalks()
            return "Removed: \(removed.text)."
        case .tally:
            guard var open = tally, let change = open.undo() else { return "There is nothing to undo." }
            tally = open
            saveTally()
            if let line = open.count(of: change.item) { return "Undone. \(Tally.spoken(line))" }
            return "Undone. \(WorkshopText.sentence(change.item)) is off the tally."
        case .dose:
            return undoDose()
        case nil:
            return "There is nothing to undo."
        }
    }

    // MARK: - Ingredient watch

    private func checkIngredients(snapshot: Snapshot, progress: Progress) async -> String {
        let list = watchList
        let watching = list.names
        // No picture is taken when there is nothing to look for.
        guard !watching.isEmpty else {
            return IngredientWatch.spoken(IngredientWatch.Report(findings: [], claims: [], sawIngredients: false, wordCount: 0), watching: [])
        }
        guard let first = await labelText(snapshot) else { return Self.noPicture }
        var report = IngredientWatch.scan(first, watched: list.allergens, custom: list.custom)
        if report.findings.isEmpty, report.sawIngredients {
            // "Nothing found" is the answer that can hurt someone, so it is never given
            // on one look.
            progress("Looking again to be sure.")
            if let second = await labelText(snapshot) {
                report = IngredientWatch.merged(report, IngredientWatch.scan(second, watched: list.allergens, custom: list.custom))
            } else {
                return "I could only read the label once, and found none of your words that time. Ask me again so I can check twice."
            }
        }
        return IngredientWatch.spoken(report, watching: watching)
    }

    private func watch(_ item: String) -> String {
        guard let name = addIngredient(item) else {
            return "\(WorkshopText.sentence(item)) is already on your list, or the list is full."
        }
        return Allergen.named(item) != nil
            ? "Added \(name). I look for: \(WorkshopText.list(watchList.names))."
            : "Added \(name). I will look for those exact words. I do not know the other names it goes by."
    }

    private func unwatch(_ item: String) -> String {
        guard let name = watchList.unwatch(item) else { return "\(WorkshopText.sentence(item)) is not on your list." }
        saveWatchList()
        return "Removed \(name)."
    }

    /// Adds something to look for. Returns its name, or nil when it was already there or
    /// the list is full.
    @discardableResult
    func addIngredient(_ item: String) -> String? {
        guard let name = watchList.watch(item) else { return nil }
        saveWatchList()
        return name
    }

    func setAllergen(_ id: String, on: Bool) {
        watchList.set(id, on: on)
        saveWatchList()
    }

    func removeIngredient(_ word: String) {
        watchList.custom.removeAll { $0 == word }
        saveWatchList()
    }

    private func saveWatchList() {
        if watchList.isEmpty {
            AccessStore.remove(Self.watchFile)
        } else {
            AccessStore.save(watchList, to: Self.watchFile)
        }
    }

    // MARK: - Dose guard

    private func doseFromLabel(snapshot: Snapshot, progress: Progress) async -> String {
        guard let first = await label(snapshot) else { return Self.noPicture }
        guard first.product != nil else {
            return "I could not read a medicine name. Hold the label closer, or say \"log a dose of\" and the name."
        }
        progress("Reading it once more to be sure.")
        let second = await label(snapshot)
        switch TwoLooks.settle(first.product, second?.product) {
        case .unread:
            return "I could not read a medicine name. Hold the label closer, or say \"log a dose of\" and the name."
        case .disagreed(let one, let two):
            if two.isEmpty {
                return "I read \(one), but could not read it a second time to be sure. I have not logged anything. Hold the label still and say \"I'm taking this\" again, or say \"log a dose of\" and the name."
            }
            return "I read two different names: \(one), and \(two). I have not logged anything. Say \"log a dose of\" and the name."
        case .agreed(let name):
            let firstGap = DoseGuard.gapHours(inDirections: first.directions)
            let secondGap = second.flatMap { DoseGuard.gapHours(inDirections: $0.directions) }
            // A gap is used only when both looks read the same one.
            return logDose(name, gapHours: firstGap == secondGap ? firstGap : nil, source: .label, force: false)
        }
    }

    private func logDose(_ name: String, gapHours: Double?, source: Dose.Source, force: Bool) -> String {
        let now = Date()
        if !force, case .tooSoon(let last, let ago, let gap, let fromLabel) =
            doses.check(name, gapHours: gapHours, fallbackHours: settings.doseGapHours, now: now) {
            heldDose = (name, gapHours, source, now)
            return DoseGuard.spokenTooSoon(last: last, ago: ago, gapHours: gap, fromLabel: fromLabel, calendar: calendar)
        }
        let before = doses.last(of: name)
        let dose = doses.log(name, gapHours: gapHours, source: source, now: now)
        saveDoses()
        lastAdded = .dose
        var line = DoseGuard.spokenLogged(dose, calendar: calendar)
        if let before, now.timeIntervalSince(before.at) < 48 * 3_600 {
            line += " The one before was \(WorkshopText.span(now.timeIntervalSince(before.at))) ago."
        }
        return line
    }

    private func undoDose() -> String {
        guard let removed = doses.removeLast() else { return "The medicine log is empty." }
        saveDoses()
        lastAdded = nil
        return "Removed \(removed.name), logged at \(WorkshopText.clock(removed.at, calendar: calendar, locale: .current))."
    }

    func eraseDoses() {
        doses.removeAll()
        heldDose = nil
        AccessStore.remove(Self.dosesFile)
    }

    private func saveDoses() {
        AccessStore.save(doses, to: Self.dosesFile)
    }

    // MARK: - Council

    private func council(_ question: String, photo: Bool, snapshot: Snapshot) async -> String {
        let names = bots.map(\.name)
        guard names.count >= 2 else {
            return "The council needs at least two assistants. Add them in Settings, under My Assistant."
        }
        guard SettingsManager.shared.settings.relayEndpoint != nil else {
            return RelayError.notConfigured.localizedDescription
        }
        let jpeg = photo ? await snapshot() : nil
        let request = Council.prompt(question, withPhoto: jpeg != nil)
        // Each assistant is asked on its own, so one that never answers costs the others nothing.
        var replies: [(bot: String, text: String)] = []
        await OwnAssistantService.shared.askEach(
            transcript: request, cleaned: request, intent: "council", bots: names, images: jpeg.map { [$0] } ?? []
        ) { bot, text in
            replies.append((bot, text))
        }
        // The wearer said stop while they were voting.
        guard !Task.isCancelled else { return "" }
        let verdict = Council.verdict(replies: replies.filter { !$0.text.isEmpty }, asked: names)
        guard !verdict.ballots.isEmpty else { return "Nobody on the council answered." }
        note(.council, "\(question)? \(verdict.tally)")
        for ballot in verdict.ballots {
            TaskLog.append(bot: ballot.bot, request: "Council: \(question)", result: "\(ballot.choice.rawValue). \(ballot.reason)")
        }
        let spoken = Council.spoken(verdict)
        return photo && jpeg == nil ? "I couldn't get a picture, so they voted without one. \(spoken)" : spoken
    }

    // MARK: - Relay race

    private func run(_ plan: RelayRace.Plan, progress: Progress) async -> String {
        // A name in the plan is a name on the roster: the parser matched against it.
        var earlier: [(step: RelayRace.Step, answer: String)] = []
        for (index, step) in plan.steps.enumerated() {
            if index == 0 {
                progress("\(plan.spokenRoute). Asking \(step.bot).")
            } else {
                progress("\(plan.steps[index - 1].bot) is done. Passing it to \(step.bot).")
            }
            let request = RelayRace.prompt(for: step, number: index + 1, of: plan.steps.count, earlier: earlier)
            do {
                let replies = try await OwnAssistantService.shared.ask(
                    transcript: request, cleaned: request, images: [], intent: "relay", targetBot: step.bot
                )
                let answer = Self.joined(replies)
                guard !answer.isEmpty else { return stopped(at: index, plan: plan, reason: "") }
                TaskLog.append(bot: step.bot, request: step.task, result: answer)
                earlier.append((step, answer))
            } catch is CancellationError {
                return ""
            } catch {
                return index == 0 ? Self.failure(error) : stopped(at: index, plan: plan, reason: Self.failure(error))
            }
        }
        guard let last = earlier.last else { return "Nobody answered." }
        note(.relay, "\(plan.spokenRoute): \(plan.steps[0].task)")
        return "\(last.step.bot) says: \(last.answer)"
    }

    private func stopped(at index: Int, plan: RelayRace.Plan, reason: String) -> String {
        var line = RelayRace.spokenStopped(at: index, plan: plan)
        if !reason.isEmpty { line += " \(reason)" }
        if index > 0 { line += " What \(WorkshopText.list(plan.steps[..<index].map(\.bot))) said is in the task history." }
        return line
    }

    // MARK: - Standing orders

    private func addOrder(_ trigger: StandingOrder.Trigger, _ action: StandingOrder.Action) -> String {
        guard orders.count < StandingOrders.limit else {
            return "You already have \(StandingOrders.limit) standing orders. Delete one first."
        }
        if case .ask(let bot?, _) = action, resolve(bot) == nil { return unknownBot(bot) }
        let order = StandingOrder(trigger: trigger, action: action)
        orders.append(order)
        saveOrders()
        return "Standing order \(orders.count). \(order.summary). It runs while Phoenix Fox is open."
    }

    private func spokenOrders() -> String {
        guard !orders.isEmpty else {
            return "You have no standing orders. Say, for example, \"whenever I put my glasses on, ask Fire Fox for my brief\"."
        }
        return orders.enumerated()
            .map { "\($0.offset + 1): \($0.element.summary)\($0.element.enabled ? "" : ", switched off")." }
            .joined(separator: " ")
    }

    func removeOrder(_ id: UUID) {
        orders.removeAll { $0.id == id }
        saveOrders()
    }

    func setOrder(_ id: UUID, enabled: Bool) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].enabled = enabled
        saveOrders()
    }

    private func saveOrders() {
        AccessStore.save(orders, to: Self.ordersFile)
    }

    /// Starts watching the glasses and the clock for standing orders and place notes.
    /// Safe to call more than once.
    func start() {
        guard watchers.isEmpty else { return }
        let link = GlassesLink.shared
        link.$worn.removeDuplicates().dropFirst().filter { $0 }
            .sink { [weak self] _ in self?.happened(.putOn) }
            .store(in: &watchers)
        link.$takenOff.removeDuplicates().dropFirst().filter { $0 }
            .sink { [weak self] _ in self?.happened(.takenOff) }
            .store(in: &watchers)
        link.$battery.compactMap { $0 }.removeDuplicates()
            .sink { [weak self] level in self?.happened(.battery(level)) }
            .store(in: &watchers)
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                self?.happened(.tick)
            }
        }
    }

    private func happened(_ event: StandingOrders.Event) {
        let settings = self.settings
        if settings.standingOrders, !orders.isEmpty {
            let fired = StandingOrders.fire(event, orders: &orders, now: Date(), calendar: calendar)
            if !fired.isEmpty {
                saveOrders()
                Task { await self.carryOut(fired, quietly: event == .takenOff) }
            }
        }
        if event == .putOn, settings.placeNotes, settings.offerPlaceNotes, !notes.notes.isEmpty {
            Task { await self.offerNotes() }
        }
    }

    /// - Parameter quietly: The glasses are off, so nothing is spoken and answers go in
    ///   the task log.
    private func carryOut(_ fired: [StandingOrder], quietly: Bool) async {
        for order in fired {
            switch order.action {
            case .say(let line):
                if !quietly { await sayWhenQuiet(line) }
            case .ask(let spoken, let text):
                guard let bot = resolve(spoken) else { continue }
                let replies = try? await OwnAssistantService.shared.ask(
                    transcript: text, cleaned: text, images: [], intent: "standing-order", targetBot: bot.name
                )
                let answer = Self.joined(replies ?? [])
                TaskLog.append(bot: bot.name, request: order.summary, result: answer.isEmpty ? "No answer." : answer)
                if !quietly, !answer.isEmpty {
                    await sayWhenQuiet("\(bot.name) says: \(answer)")
                }
            }
            note(.standingOrder, order.summary)
        }
    }

    /// Says a line nobody asked for, once nothing else is being said. A line that is not
    /// urgent is dropped if it lands on top of speech, and two of these can come due at
    /// the same moment: a standing order and a place note when the glasses go on.
    private func sayWhenQuiet(_ line: String) async {
        var waited = 0
        while waited < 40, TTSService.shared.isSpeaking || NeuralSpeech.isAnySpeaking {
            try? await Task.sleep(for: .milliseconds(500))
            waited += 1
        }
        TTSService.shared.announce(line, urgent: false)
    }

    // MARK: - Place notes

    private func leaveNote(_ text: String) async -> String {
        guard !text.isEmpty else { return "Say the note after \"leave a note here\"." }
        let found = await WalkingGuide.shared.locate()
        guard let fix = found.fix else { return found.problem }
        guard fix.accuracy <= PlaceNotes.worstAccuracy else {
            return "I can't tell closely enough where you are to pin a note here. Try again near a window or outside."
        }
        let note = notes.leave(text, latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.accuracy, at: Date())
        saveNotes()
        lastReadNote = note.id
        self.note(.placeNote, "Left a note: \(note.text)")
        return "Note left here."
    }

    private func notesHere() async -> String {
        guard !notes.notes.isEmpty else { return "You have not left any notes anywhere yet." }
        let found = await WalkingGuide.shared.locate()
        guard let fix = found.fix else { return found.problem }
        let near = notes.near(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.accuracy).map(\.note)
        lastReadNote = near.first?.id
        return PlaceNotes.spoken(near)
    }

    private func deleteNote() async -> String {
        var target = lastReadNote
        if target == nil {
            let found = await WalkingGuide.shared.locate()
            guard let fix = found.fix else { return found.problem }
            target = notes.near(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.accuracy).first?.note.id
        }
        guard let target, let removed = notes.remove(target) else { return "There is no note here to delete." }
        saveNotes()
        lastReadNote = nil
        return "Deleted the note: \(removed.text)"
    }

    private func offerNotes() async {
        // Putting the glasses on must not make the system ask for location.
        guard WalkingGuide.shared.canLocateWithoutAsking else { return }
        guard let fix = await WalkingGuide.shared.locate().fix else { return }
        let due = notes.offer(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.accuracy, now: Date())
        guard let line = PlaceNotes.spokenOffer(due) else { return }
        saveNotes()
        lastReadNote = due.first?.id
        await sayWhenQuiet(line)
    }

    func removeNote(_ id: UUID) {
        _ = notes.remove(id)
        saveNotes()
    }

    private func saveNotes() {
        AccessStore.save(notes, to: Self.notesFile)
    }

    // MARK: - Close the day

    private func closeDay(with spoken: String?) async -> String {
        let today = journal.entries(on: Date(), calendar: calendar)
        // Nothing is sent, and nothing is spent, for an empty day.
        guard let sheet = DaySheet.compose(today, day: Date(), calendar: calendar) else {
            return "Nothing is recorded for today, so there is nothing to close."
        }
        guard let bot = resolve(spoken) else { return unknownBot(spoken) }
        let request = DaySheet.prompt(sheet)
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: request, cleaned: request, images: [], intent: "day-sheet", targetBot: bot.name
            )
            let answer = Self.joined(replies)
            TaskLog.append(bot: bot.name, request: "Day sheet", result: answer)
            return answer.isEmpty ? "Day sheet sent to \(bot.name)." : "Day sheet sent. \(bot.name) says: \(answer)"
        } catch {
            return Self.failure(error)
        }
    }

    private func note(_ kind: WorkshopJournal.Kind, _ summary: String) {
        journal.note(kind, summary, at: Date())
        AccessStore.save(journal, to: Self.journalFile)
    }

    // MARK: - Skills

    private func run(_ match: Skills.Match, snapshot: Snapshot) async -> String {
        let skill = match.skill
        guard let bot = resolve(skill.bot) else {
            return "The skill \(skill.name) asks for an assistant called \(skill.bot ?? ""), and you don't have one. Change it in Settings, under Workshop."
        }
        var images: [Data] = []
        var text: String?
        var place: String?
        var time: String?
        if skill.capture.contains(.photo) {
            guard let jpeg = await snapshot() else { return "I couldn't get a picture, so I did not run \(skill.name)." }
            images = [jpeg]
        }
        if skill.capture.contains(.text) {
            guard let read = await labelText(snapshot) else { return "I couldn't get a picture, so I did not run \(skill.name)." }
            text = String(read.prefix(3_000))
        }
        if skill.capture.contains(.place) {
            if let fix = await WalkingGuide.shared.locate().fix {
                // Four decimal places is about ten meters: enough for "which shop", not for "which shelf".
                place = String(format: "%.4f, %.4f", fix.coordinate.latitude, fix.coordinate.longitude)
            }
        }
        if skill.capture.contains(.time) {
            time = WorkshopText.stamp(Date(), date: .medium, time: .short, calendar: calendar, locale: .current)
        }
        let request = skill.request(slot: match.slot, text: text, place: place, time: time)
        do {
            let replies = try await OwnAssistantService.shared.ask(
                transcript: request, cleaned: request, images: images, intent: "skill:\(skill.id)", targetBot: bot.name
            )
            let answer = Self.joined(replies)
            TaskLog.append(bot: bot.name, request: skill.name, result: answer)
            note(.skill, skill.name)
            switch skill.speak {
            case .quiet: return "Sent."
            case .reply: return answer.isEmpty ? "\(bot.name) did not answer." : answer
            }
        } catch {
            return Self.failure(error)
        }
    }

    /// Adds a skill from its file. Throws a `SkillError` that says what is wrong with it.
    @discardableResult
    func install(skillFile: String) throws -> Skill {
        let skill = try Skill.decode(skillFile)
        try Skills.install(skill, into: &skills)
        saveSkills()
        return skill
    }

    func install(_ skill: Skill) throws {
        try Skills.install(skill, into: &skills)
        saveSkills()
    }

    func removeSkill(_ id: String) {
        skills.removeAll { $0.id == id }
        saveSkills()
    }

    private func saveSkills() {
        AccessStore.save(skills, to: Self.skillsFile)
    }

    // MARK: - Shared

    /// Erases everything the workshop keeps on this phone.
    func eraseEverything() {
        walks.flatMap(\.photos).forEach(AccessStore.remove)
        walks = []
        tally = nil
        orders = []
        skills = []
        notes = PlaceNotes()
        journal.removeAll()
        watchList = WatchList()
        lastAdded = nil
        lastReadNote = nil
        eraseDoses()
        for file in [Self.walksFile, Self.tallyFile, Self.ordersFile, Self.skillsFile, Self.notesFile, Self.journalFile, Self.watchFile] {
            AccessStore.remove(file)
        }
    }

    /// The assistant a spoken name means. Nil in means the default assistant. Nil out
    /// means there is no assistant by that name.
    private func resolve(_ spoken: String?) -> AssistantBot? {
        let roster = bots
        guard let spoken, !spoken.isEmpty else { return AssistantRoster.defaultBot(in: roster) }
        let wanted = WorkshopText.words(spoken).joined(separator: " ")
        return roster.first { WorkshopText.words($0.name).joined(separator: " ") == wanted }
    }

    private func unknownBot(_ spoken: String?) -> String {
        "You don't have an assistant called \(spoken ?? "that"). Your assistants are \(WorkshopText.list(bots.map(\.name)))."
    }

    /// A picture good enough for small print: a whole-sensor still when the build may
    /// take one, and a frame from the stream when it may not.
    private func picture(_ snapshot: Snapshot) async -> Data? {
        if let large = await GlassesManager.shared.captureStill(.reading) { return large }
        return await snapshot()
    }

    /// The words in view, in reading order, one line of the label per line.
    private func labelText(_ snapshot: Snapshot) async -> String? {
        guard let jpeg = await picture(snapshot) else { return nil }
        // No language correction: it turns ingredient and drug names into ordinary words.
        let fragments = await AccessVision.text(in: jpeg, corrected: false)
        return ReadingOrder.lines(fragments).map(\.text).joined(separator: "\n")
    }

    private func label(_ snapshot: Snapshot) async -> LabelReader.Reading? {
        guard let jpeg = await picture(snapshot) else { return nil }
        let fragments = await AccessVision.text(in: jpeg, corrected: false)
        return LabelReader.medicine(ReadingOrder.lines(fragments))
            ?? LabelReader.Reading(product: nil, directions: [], expiry: nil, warnings: [], other: [], doubtful: false)
    }

    private static func joined(_ replies: [RelayReply]) -> String {
        replies.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cuts text to a limit at a line break, and says how many lines were left out.
    private static func fitted(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var kept: [Substring] = []
        var length = 0
        for line in lines {
            guard length + line.count + 1 <= limit - 50 else { break }
            kept.append(line)
            length += line.count + 1
        }
        return kept.joined(separator: "\n") + "\n(\(lines.count - kept.count) more lines did not fit)"
    }

    /// What to say when the relay could not be asked. Nothing, when the wearer stopped it.
    private static func failure(_ error: Error) -> String {
        if error is CancellationError { return "" }
        return error.localizedDescription
    }

    private static let noPicture = "I couldn't get a picture from the glasses. Check that they're connected and on, then try again."
    private static let noWalk = "No walk-through is open. Say \"start a walk-through\", and a name if you like."
    private static let noTally = "No tally is open. Say \"start a tally\", and a name if you like."
}
