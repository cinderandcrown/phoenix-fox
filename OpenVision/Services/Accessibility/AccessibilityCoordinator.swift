// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Carries out the accessibility suite's spoken commands.
//
// A sentence is offered here before it reaches the assistant. If it is one of the suite's
// commands, this does the work and returns the line to say. Otherwise it returns nil and
// the sentence goes on as before. Reading, colors, money, labels, and faces are worked out
// on the phone, so they answer with no signal and cost nothing.

import Foundation
import UIKit

@MainActor
final class AccessibilityCoordinator: ObservableObject {
    static let shared = AccessibilityCoordinator()

    /// Takes a fresh photo from the glasses. Nil when the glasses camera gave nothing.
    typealias Snapshot = @MainActor () async -> Data?

    @Published private(set) var routines: [Routine]
    @Published private(set) var task: TaskRun?
    @Published private(set) var reminders: [PersonReminder]

    /// Set by the voice screen: applies the wearer's "give me more time" choice to the
    /// microphone's pause timers.
    var applyTiming: ((AccessibilitySettings) -> Void)?

    private var reading: ReadingSession?
    private var focus: AccessCommand.Focus = .none
    private var trail: [ActivityEntry]
    private var pending: PendingConfirmation<Action>?
    private var nudger: Task<Void, Never>?

    /// What waits for a spoken yes.
    private enum Action: Sendable {
        case enroll(name: String)
        case forgetAllFaces
        case startGuide
        case emergencyCall
        case setEmergencyContact(name: String, number: String)
        case deleteRoutine(name: String)

        /// Whether the yes has to be said aloud: where it reaches another person, where
        /// the wearer's safety rests on it, or where it erases faces. A nod is enough
        /// for a change to the wearer's own lists that they asked for a moment ago.
        var needsSpokenYes: Bool {
            switch self {
            case .enroll, .forgetAllFaces, .startGuide, .emergencyCall: return true
            case .setEmergencyContact, .deleteRoutine: return false
            }
        }
    }

    /// Which answers a nod or a shake of the head may give right now.
    var headAnswerPolicy: HeadAnswerPolicy {
        guard let pending, !pending.expired(at: Date()) else { return .none }
        return pending.action.needsSpokenYes ? .noOnly : .yesOrNo
    }

    private init() {
        routines = AccessStore.load([Routine].self, from: "routines") ?? []
        reminders = AccessStore.load([PersonReminder].self, from: "reminders") ?? []
        trail = AccessStore.load([ActivityEntry].self, from: "trail") ?? []
        task = AccessStore.load(TaskRun.self, from: "task")
        if let task, !task.finished {
            focus = .task
            startNudging()
        }
    }

    private var settings: AccessibilitySettings {
        get { SettingsManager.shared.settings.accessibility }
        set { SettingsManager.shared.settings.accessibility = newValue }
    }

    /// Makes the running services match the settings. Called when listening starts, which
    /// brings back what was on when the app last ran, and after a change in settings.
    func apply() {
        applyTiming?(settings)
        if !settings.soundAlerts {
            SoundAlertService.shared.stop()
        } else if SoundAlertService.shared.kinds != settings.soundKinds || !SoundAlertService.shared.isOn {
            _ = SoundAlertService.shared.start(kinds: settings.soundKinds)
        }
    }

    // MARK: - The turn

    /// Handles one sentence. Returns the line to say, or nil when the sentence is not for
    /// the accessibility suite.
    func handle(_ text: String, snapshot: @escaping Snapshot) async -> String? {
        if let waiting = pending {
            pending = nil
            if !waiting.expired(at: Date()) {
                switch Confirmation.parse(text) {
                case .yes?:
                    return await confirmed(waiting.action, snapshot: snapshot)
                case .no?:
                    return "Okay, I won't."
                case .again?:
                    pending = PendingConfirmation(action: waiting.action, question: waiting.question, askedAt: Date())
                    return waiting.question
                case nil:
                    // Something else was said. The question is dropped, and the sentence is
                    // treated as a new command.
                    break
                }
            }
        }
        let context = AccessCommand.Context(
            focus: focus,
            guiding: GuideMode.shared.isOn,
            walking: WalkingGuide.shared.isActive
        )
        guard let command = AccessCommand.parse(text, context: context) else { return nil }
        return await perform(command, snapshot: snapshot)
    }

    /// Runs one command. Returns the line to say, or nil when the only thing to do is to
    /// stop talking, which the caller's own "stop" handling does.
    func perform(_ command: AccessCommand, snapshot: @escaping Snapshot) async -> String? {
        switch command {
        // Seeing
        case .read(let scope): return await read(scope, snapshot: snapshot)
        case .readMore: return turnPage { $0.advance() } ?? "That was the end. Say read this to read something else."
        case .readBack: return turnPage { $0.goBack() } ?? "This is the beginning."
        case .readAgain: return turnPage { _ in true }
        case .stopReading:
            reading = nil
            if focus == .reading { focus = task == nil ? .none : .task }
            return nil
        case .readLabel: return await readLabel(snapshot: snapshot)
        case .identifyMoney:
            guard let jpeg = await snapshot() else { return Self.noPicture }
            let fragments = await AccessVision.text(in: jpeg, corrected: false)
            return CurrencyReader.read(fragments.map(\.text)).spoken
        case .identifyColor:
            guard let jpeg = await snapshot() else { return Self.noPicture }
            let samples = await AccessVision.centerColors(in: jpeg)
            guard !samples.isEmpty else { return "I couldn't read the picture. Try again." }
            return ColorNamer.describe(samples).spoken
        case .describeScene: return await describeScene(snapshot: snapshot)
        case .find(let thing): return await find(thing, snapshot: snapshot)

        // Faces
        case .whoIsThis: return await whoIsThis(snapshot: snapshot)
        case .rememberFace(let name):
            guard PrivacyFeatureFlags.faceRecognition, settings.faceRecognition else { return Self.facesOff }
            return ask("Has \(name) agreed to let me save their face on this phone? Say yes or no.", then: .enroll(name: name))
        case .forgetFace(let name): return AccessFaces.shared.forget(name: name)
        case .forgetAllFaces:
            guard !AccessFaces.shared.records.isEmpty else { return "I haven't saved anyone's face." }
            return ask("Delete every saved face? Say yes or no.", then: .forgetAllFaces)
        case .faceRecognition(let on):
            guard PrivacyFeatureFlags.faceRecognition else { return Self.facesOff }
            settings.faceRecognition = on
            return on
                ? "Face recognition is on. I only recognize people you save, and I ask for their permission first. Face data stays on this phone."
                : "Face recognition is off. Saved faces are kept until you say forget all faces."

        // Getting around
        case .guide(let on):
            guard on else { return GuideMode.shared.stop() }
            guard settings.guideSafetyAccepted else {
                return ask(GuideMode.safetyNotice + " Say yes to start, or no.", then: .startGuide)
            }
            note(.walk, "started Guide mode")
            return GuideMode.shared.start()
        case .walk(let place):
            let line = await WalkingGuide.shared.start(to: place)
            if WalkingGuide.shared.isActive { note(.walk, "started walking to \(WalkingGuide.shared.destination)") }
            return line
        case .stopWalking: return WalkingGuide.shared.stop()
        case .nextTurn: return WalkingGuide.shared.status()
        case .whereAmI: return await WalkingGuide.shared.whereAmI()
        case .emergencyCall:
            guard !settings.emergencyContactNumber.isEmpty else {
                return "You haven't set an emergency contact. Say set my emergency contact to, then a name from your contacts. For an emergency right now, say Hey Meta, call, then a name."
            }
            return ask("Call \(emergencyName)? Say yes or no.", then: .emergencyCall)
        case .setEmergencyContact(let name):
            guard let number = await PhoenixFoxFeatures.contactNumber(matching: name) else {
                return "I couldn't find a phone number for \(name) in your contacts. You can also type a number in Accessibility settings."
            }
            let ending = number.suffix(4).map(String.init).joined(separator: " ")
            return ask("Make \(name), number ending \(ending), your emergency contact? Say yes or no.", then: .setEmergencyContact(name: name, number: number))

        // Hearing
        case .captions(let on):
            if on { note(.captions, "turned on live captions") }
            return on ? LiveCaptions.shared.start() : LiveCaptions.shared.stop()
        case .soundAlerts(let on):
            settings.soundAlerts = on
            guard on else {
                SoundAlertService.shared.stop()
                return "Sound alerts are off."
            }
            return SoundAlertService.shared.start(kinds: settings.soundKinds)
        case .whatWasSaid: return LiveCaptions.shared.recentSpoken()
        case .saveTranscript: return LiveCaptions.shared.save()
        case .clearTranscript: return LiveCaptions.shared.clear()

        // Speech and movement
        case .pace(let pace):
            settings.pace = pace
            switch pace {
            case .slow: return "Okay. I'll speak more slowly."
            case .normal: return "Okay. Back to my normal speed."
            case .fast: return "Okay. I'll speak faster."
            }
        case .extraTime(let on):
            settings.extraTime = on
            applyTiming?(settings)
            return on
                ? "Okay. I'll wait longer for you to finish before I act. Take the time you need."
                : "Okay. Back to the normal wait."
        case .help: return AccessHelp.spoken

        // Tasks and memory
        case .startTask(let name): return await startTask(name)
        case .teachRoutine(let name, let steps):
            saveRoutine(Routine(name: name, steps: steps))
            return "Saved \(name), \(steps.count) step\(steps.count == 1 ? "" : "s"). Say start my \(name) routine when you want it."
        case .listRoutines:
            return routines.isEmpty
                ? "You have no saved routines. Say new routine called, a name, the steps are, then each step."
                : "Your routines are \(FaceLedger.list(routines.map(\.name)))."
        case .deleteRoutine(let name):
            guard let routine = routine(named: name) else { return "I don't have a routine called \(name)." }
            return ask("Delete the \(routine.name) routine? Say yes or no.", then: .deleteRoutine(name: routine.name))
        case .taskNext: return step { $0.next(at: Date()) }
        case .taskBack: return step { $0.back(at: Date()) }
        case .taskRepeat: return step { $0.repeated(at: Date()) }
        case .taskWhere: return task?.summary ?? Self.noTask
        case .taskStop:
            guard let run = task else { return Self.noTask }
            endTask()
            return "Stopped \(run.routine.name) at \(run.position.lowercased())."
        case .whatWasIDoing: return whatWasIDoing()
        case .recall(let on):
            settings.activityRecall = on
            if !on { forgetTrail() }
            return on
                ? "Activity recall is on. I'll keep a short list of the tasks, walks, and reading you start with me, for one day, on this phone only. Say what was I doing at any time."
                : "Activity recall is off, and the list is erased."
        case .forgetActivity:
            forgetTrail()
            return "Done. The activity list is erased."
        case .remindWhenSeeing(let person, let note):
            reminders.append(PersonReminder(person: person, note: note, createdAt: Date()))
            AccessStore.save(reminders, to: "reminders")
            var line = "I'll remind you to \(note) when I recognize \(person)."
            if !settings.faceRecognition {
                line += " Face recognition is off, so turn it on for this to work."
            } else if !AccessFaces.shared.knows(person) {
                line += " I don't have \(person)'s face yet. With their permission, say remember this person as \(person)."
            }
            return line
        }
    }

    /// Starts Guide mode once the wearer has heard or read the safety notice and agreed.
    func startGuideAfterSafetyNotice() -> String {
        settings.guideSafetyAccepted = true
        note(.walk, "started Guide mode")
        return GuideMode.shared.start()
    }

    private func ask(_ question: String, then action: Action) -> String {
        pending = PendingConfirmation(action: action, question: question, askedAt: Date())
        return question
    }

    private func confirmed(_ action: Action, snapshot: Snapshot) async -> String {
        switch action {
        case .enroll(let name):
            guard let jpeg = await snapshot() else { return Self.noPicture }
            return await AccessFaces.shared.enroll(name: name, jpeg: jpeg, consentAt: Date())
        case .forgetAllFaces:
            return AccessFaces.shared.forgetAll()
        case .startGuide:
            return startGuideAfterSafetyNotice()
        case .emergencyCall:
            return await callEmergencyContact()
        case .setEmergencyContact(let name, let number):
            settings.emergencyContactName = name
            settings.emergencyContactNumber = number
            return "\(name) is your emergency contact. Say call my emergency contact when you need them."
        case .deleteRoutine(let name):
            routines.removeAll { $0.name == name }
            if routines.isEmpty { AccessStore.remove("routines") } else { AccessStore.save(routines, to: "routines") }
            return "Deleted the \(name) routine."
        }
    }

    // MARK: - Reading

    /// A picture for reading print. The glasses' photo capability uses the whole sensor,
    /// which resolves small print that a frame of the video stream blurs. When this build
    /// may not use it, or the camera is already streaming, a frame of the stream is used.
    private func printPicture(_ snapshot: Snapshot) async -> Data? {
        if let large = await GlassesManager.shared.captureStill(.reading) { return large }
        return await snapshot()
    }

    private func read(_ scope: AccessCommand.ReadScope, snapshot: Snapshot) async -> String {
        switch scope {
        case .sign:
            // A sign is large print, and on a walk the answer has to be quick.
            guard let jpeg = await snapshot() else { return Self.noPicture }
            let fragments = await AccessVision.text(in: jpeg, corrected: true, fast: true)
            let words = ReadingOrder.headline(fragments)
            guard !words.isEmpty else { return "I don't see a sign I can read. Face it and ask again." }
            note(.read, "asked me to read a sign")
            return "It says: " + words.joined(separator: ". ") + "."
        case .everything:
            guard let jpeg = await printPicture(snapshot) else { return Self.noPicture }
            let fragments = await AccessVision.text(in: jpeg, corrected: true)
            return startReading(ReadingOrder.paragraphs(fragments), lead: "")
        }
    }

    private func startReading(_ paragraphs: [String], lead: String) -> String {
        let session = ReadingSession(paragraphs: paragraphs)
        guard !session.isEmpty else {
            return "I don't see any text. Hold it about a forearm's length away, in good light, and say read this again."
        }
        reading = session
        focus = .reading
        note(.read, "asked me to read something")
        return lead + session.spoken
    }

    /// Moves within what is being read, then reads that part. Nil when the move was not
    /// possible, so the caller can say why.
    private func turnPage(_ move: (inout ReadingSession) -> Bool) -> String? {
        guard var session = reading else { return "I'm not reading anything. Point at some text and say read this." }
        guard move(&session) else { return nil }
        reading = session
        focus = .reading
        return session.spoken
    }

    private func readLabel(snapshot: Snapshot) async -> String {
        guard let jpeg = await printPicture(snapshot) else { return Self.noPicture }
        // No language correction here: it "fixes" drug names into ordinary words.
        let fragments = await AccessVision.text(in: jpeg, corrected: false)
        let lines = ReadingOrder.lines(fragments)
        if let label = LabelReader.medicine(lines) {
            note(.read, "asked me to read a medicine label")
            return label.spoken
        }
        return startReading(ReadingOrder.paragraphs(fragments), lead: "This doesn't look like a medicine label. ")
    }

    // MARK: - Scene

    private func describeScene(snapshot: Snapshot) async -> String {
        guard let jpeg = await snapshot() else { return Self.noPicture }
        if let small = ImageBudget.jpeg(jpeg), let described = await SceneDescriber.scene(in: small) {
            return described
        }
        return SceneSummary.sentence(await AccessVision.sightings(in: jpeg))
    }

    private func find(_ thing: String, snapshot: Snapshot) async -> String {
        guard let jpeg = await snapshot() else { return Self.noPicture }
        if let answer = ObjectFinder.answer(for: thing, in: await AccessVision.sightings(in: jpeg)) {
            return answer
        }
        if let small = ImageBudget.jpeg(jpeg), let answer = await SceneDescriber.locate(thing, in: small) {
            return answer
        }
        return "I don't see a \(thing) from here. Turn slowly and ask again."
    }

    // MARK: - Faces

    private func whoIsThis(snapshot: Snapshot) async -> String {
        guard PrivacyFeatureFlags.faceRecognition, settings.faceRecognition else { return Self.facesOff }
        guard let jpeg = await snapshot() else { return Self.noPicture }
        let result = await AccessFaces.shared.identify(jpeg: jpeg)
        let notes = result.names.flatMap { name in
            takeReminders(for: name).map { "Reminder for \(name): \($0)." }
        }
        return ([result.spoken] + notes).joined(separator: " ")
    }

    /// Guide mode recognized someone. Says any reminder that was waiting for them.
    func saw(_ name: String) {
        for reminder in takeReminders(for: name) {
            TTSService.shared.announce("Reminder for \(name): \(reminder).", urgent: true)
        }
    }

    private func takeReminders(for name: String) -> [String] {
        let due = PersonReminder.take(for: name, from: &reminders)
        guard !due.isEmpty else { return [] }
        if reminders.isEmpty { AccessStore.remove("reminders") } else { AccessStore.save(reminders, to: "reminders") }
        return due
    }

    func removeReminder(_ reminder: PersonReminder) {
        reminders.removeAll { $0 == reminder }
        if reminders.isEmpty { AccessStore.remove("reminders") } else { AccessStore.save(reminders, to: "reminders") }
    }

    /// Saves a routine, replacing one with the same name.
    func saveRoutine(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        routines.append(routine)
        AccessStore.save(routines, to: "routines")
    }

    func removeRoutine(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        if routines.isEmpty { AccessStore.remove("routines") } else { AccessStore.save(routines, to: "routines") }
    }

    // MARK: - Emergency contact

    private var emergencyName: String {
        settings.emergencyContactName.isEmpty ? "your emergency contact" : settings.emergencyContactName
    }

    private func callEmergencyContact() async -> String {
        let digits = settings.emergencyContactNumber.filter { $0.isNumber || $0 == "+" }
        let handsFree = "If you can't reach the phone, say Hey Meta, call \(emergencyName)."
        guard let url = URL(string: "tel:\(digits)"), !digits.isEmpty, await UIApplication.shared.open(url) else {
            return "I couldn't start the call from here. \(handsFree)"
        }
        // iOS does not let an app place a call by itself. It shows a Call button first.
        return "Calling \(emergencyName). Your iPhone asks you to confirm: tap Call on the screen. \(handsFree)"
    }

    // MARK: - Tasks

    private func routine(named name: String) -> Routine? {
        let wanted = name.lowercased()
        return routines.first { $0.name.lowercased() == wanted }
            ?? routines.first { $0.name.lowercased().contains(wanted) || wanted.contains($0.name.lowercased()) }
    }

    private func startTask(_ name: String) async -> String {
        var lead = ""
        var chosen = routine(named: name)
        if chosen == nil {
            guard let steps = await suggestedSteps(for: name) else {
                return "I don't have a routine called \(name). Teach me one: say new routine called \(name), the steps are, then each step."
            }
            chosen = Routine(name: name.prefix(1).uppercased() + name.dropFirst(), steps: steps)
            lead = "You haven't saved this one, so these steps come from the assistant. Check they fit before you rely on them. "
        }
        guard let routine = chosen else { return Self.noTask }
        var run = TaskRun(routine, at: Date())
        let line = run.begin(at: Date())
        task = run.finished ? nil : run
        saveTask()
        if task != nil {
            focus = .task
            startNudging()
            note(.task, "started \(routine.name)")
        }
        return lead + line
    }

    /// Steps written by the assistant for a task with no saved routine. Nil when no model
    /// can be reached or the answer was not a usable list.
    private func suggestedSteps(for name: String) async -> [String]? {
        guard SettingsManager.shared.settings.isGrokConfigured else { return nil }
        let prompt = "List the steps to \(name) as a numbered list. At most eight steps. Each step is one short, concrete action in plain words. No introduction and no closing remark."
        let system = "You write step-by-step instructions for a person who needs one simple action at a time."
        guard let answer = try? await GrokService.shared.complete(prompt, imageData: nil, system: system) else { return nil }
        let steps = Routine.steps(from: answer)
        return steps.count >= 2 ? Array(steps.prefix(10)) : nil
    }

    private func step(_ move: (inout TaskRun) -> String) -> String {
        guard var run = task else { return Self.noTask }
        let line = move(&run)
        if run.finished {
            note(.task, "finished \(run.routine.name)")
            endTask()
        } else {
            task = run
            focus = .task
            saveTask()
        }
        return line
    }

    private func endTask() {
        task = nil
        nudger?.cancel()
        nudger = nil
        if focus == .task { focus = reading == nil ? .none : .reading }
        saveTask()
    }

    private func saveTask() {
        if let task { AccessStore.save(task, to: "task") } else { AccessStore.remove("task") }
    }

    /// After four quiet minutes on one step, says the step again, once, when nothing else
    /// is being said.
    private func startNudging() {
        nudger?.cancel()
        nudger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                guard var run = self.task, let line = run.nudge(at: Date()) else { continue }
                self.task = run
                self.saveTask()
                TTSService.shared.announce(line, urgent: false)
            }
        }
    }

    // MARK: - Recall

    private func whatWasIDoing() -> String {
        var now: [String] = []
        if let task, !task.finished { now.append(task.summary) }
        if let walk = WalkingGuide.shared.summary { now.append(walk) }
        if GuideMode.shared.isOn { now.append("Guide mode is on.") }
        if LiveCaptions.shared.isOn { now.append("Live captions are on.") }
        return ActivityTrail.recall(entries: trail, inProgress: now, enabled: settings.activityRecall, now: Date())
    }

    private func note(_ kind: ActivityEntry.Kind, _ summary: String) {
        guard settings.activityRecall else { return }
        trail = ActivityTrail.appending(ActivityEntry(at: Date(), kind: kind, summary: summary), to: trail)
        AccessStore.save(trail, to: "trail")
    }

    private func forgetTrail() {
        trail = []
        AccessStore.remove("trail")
    }

    // MARK: - Lines said in more than one place

    private static let noPicture = "I couldn't get a picture from the glasses. Check that they're connected and on, then try again."
    private static let noTask = "No task is running. Say guide me through, then what you want to do."
    private static let facesOff = "Face recognition is off. Say turn on face recognition. I only recognize people who agreed to be saved."
}
