// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The workshop: the ten features chosen from docs/INNOVATION_BACKLOG.md, each with its
// own switch, what it says to use, and what it keeps. Shown only in the owner build.

import SwiftUI

struct WorkshopSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var workshop = WorkshopCoordinator.shared

    @State private var confirmingEraseDoses = false
    @State private var confirmingEraseAll = false

    private var settings: Binding<WorkshopSettings> { $settingsManager.settings.workshop }

    var body: some View {
        Form {
            Section {
                Toggle("Walk-through", isOn: settings.walkThrough)
                    .accessibilityHint("Say start a walk-through, then note, flag, or photo note as you go.")
                if !workshop.walks.isEmpty {
                    NavigationLink {
                        WalkThroughListView()
                    } label: {
                        row("Walk-throughs", count: workshop.walks.count)
                    }
                }
                Toggle("Tally", isOn: settings.tally)
                    .accessibilityHint("Say start a tally, then a number and an item.")
                if let tally = workshop.tally, !tally.isEmpty {
                    ShareLink(item: tally.csv(), subject: Text(tally.name)) {
                        Label("Share the \(tally.name) tally", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("On the job")
            } footer: {
                Text("Walk-through: \"start a walk-through at the Elm Street house\", then \"note…\", \"flag…\", or \"photo note…\" as you walk, and \"finish the walk-through\". \"Send the walk-through to Indy\" files it with its photos. A photo is taken only when you say \"photo\", with the capture light on.\n\nTally: \"start a tally for the storeroom\", then \"twelve cases of cups\", \"take away two cups\", \"how many cups\", \"undo\", and \"finish the tally\". Counting happens on the phone and costs nothing.")
            }

            Section {
                Toggle("Ingredient watch", isOn: settings.ingredientWatch)
                    .accessibilityHint("Say check the ingredients while you look at a label.")
                NavigationLink {
                    IngredientListView()
                } label: {
                    row("What to look for", count: workshop.watchList.names.count)
                }
                Toggle("Dose guard", isOn: settings.doseGuard)
                    .accessibilityHint("Say I'm taking this while you look at a medicine label.")
                Stepper(value: settings.doseGapHours, in: WorkshopSettings.gapRange, step: 1) {
                    Text("Warn inside \(Int(settingsManager.settings.workshop.doseGapHours)) hours")
                }
                .accessibilityHint("Used when the label does not say how long to wait between doses.")
                if !workshop.doses.doses.isEmpty {
                    Button("Erase the medicine log", role: .destructive) {
                        confirmingEraseDoses = true
                    }
                }
            } header: {
                Text("Health")
            } footer: {
                Text("These are aids. They are not medical devices, and they can be wrong.\n\nIngredient watch reads a label on the phone and looks for the words on your list. It reads English labels only. When it finds none of them it says so, and never says a food is safe. Read the label yourself whenever it matters.\n\nDose guard keeps a log of the doses you tell it about: \"I'm taking this\" while you look at the label, or \"log a dose of ibuprofen\". It warns when the same medicine was logged inside the time the label gives, or inside the hours set here when the label gives none. It knows only what you logged. It does not know what your doctor told you, and it does not check one medicine against another. The log is sealed on this phone and never sent anywhere, and these turns are kept out of the conversation history.")
            }

            Section {
                Toggle("Council", isOn: settings.council)
                    .accessibilityHint("Say ask the council, then a question with a yes or no answer.")
                Toggle("Relay race", isOn: settings.relayRace)
                    .accessibilityHint("Say ask one assistant to do something, then another to do the next thing.")
                Toggle("Close the day", isOn: settings.closeTheDay)
                    .accessibilityHint("Say close the day to send today's workshop notes to an assistant.")
            } header: {
                Text("Your team")
            } footer: {
                Text("Council: \"ask the council, should I take this job\". Every assistant votes yes, no, or unsure with one reason, and you hear the count and who disagreed first. A question that points at something, like \"ask the council, should I buy this\", sends what you are looking at, with the capture light on.\n\nRelay race: \"ask Indy to find three venues, then Driver to price the travel, then Rally to draft the invitation\". Each assistant gets the work of the ones before.\n\nClose the day: \"close the day\" sends today's walk-throughs, tallies, notes, votes, and skills to your main assistant for a summary and tomorrow's list. Health records are never part of it. Each of these costs one message per assistant asked.")
            }

            Section {
                Toggle("Standing orders", isOn: settings.standingOrders)
                    .accessibilityHint("Say whenever I put my glasses on, then what to say or which assistant to ask.")
                ForEach(workshop.orders) { order in
                    Toggle(order.summary, isOn: Binding(
                        get: { order.enabled },
                        set: { workshop.setOrder(order.id, enabled: $0) }
                    ))
                }
                .onDelete { offsets in
                    for id in offsets.map({ workshop.orders[$0].id }) { workshop.removeOrder(id) }
                }
            } header: {
                Text("Standing orders")
            } footer: {
                Text("\"Whenever I put my glasses on, ask Fire Fox for my brief.\" \"When the battery drops below twenty percent, say charge me.\" \"Every day at eight thirty, ask Driver what is on today.\" \"When I take my glasses off, ask Rally to file my notes.\" Up to \(StandingOrders.limit). They run only while Phoenix Fox is open, and never use the camera or the microphone. Swipe one to delete it.")
            }

            Section {
                Toggle("Place notes", isOn: settings.placeNotes)
                    .accessibilityHint("Say leave a note here, then the note.")
                Toggle("Read a note when I put my glasses on there", isOn: settings.offerPlaceNotes)
                    .disabled(!settingsManager.settings.workshop.placeNotes)
                if !workshop.notes.notes.isEmpty {
                    NavigationLink {
                        PlaceNoteListView()
                    } label: {
                        row("Notes", count: workshop.notes.notes.count)
                    }
                }
            } header: {
                Text("Places")
            } footer: {
                Text("\"Leave a note here: the breaker for the kitchen is number twelve.\" Later, in the same place, \"any notes here\". The notes and where they were left are sealed on this phone and never sent anywhere. Indoors the phone knows where you are to within a room or two at best, so a note may be offered next door.")
            }

            Section {
                Toggle("Skills", isOn: settings.skills)
                    .accessibilityHint("Skills are phrases you add that send a request to an assistant.")
                NavigationLink {
                    SkillListView()
                } label: {
                    row("Skills", count: workshop.skills.count)
                }
            } header: {
                Text("Skills")
            } footer: {
                Text("A skill is a small file that teaches Phoenix Fox one new phrase: what to capture and what to ask an assistant. It contains no code. Before you add one you see everything it captures and where it goes. The format is in docs/SKILLS.md, for anyone who wants to write one.")
            }

            Section {
                NavigationLink {
                    LookToTalkSettingsView()
                } label: {
                    HStack {
                        Text("Look to Talk")
                        Spacer()
                        Text(settingsManager.settings.workshop.lookToTalk ? "On" : "Off")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("After the first release")
            } footer: {
                Text("Look at an assistant's chat window on your computer and talk to it without saying its name. It is off until you turn it on here, and it is not one of the ten above: it was written after them and has not been tried on glasses yet.")
            }

            Section {
                Button("Erase everything the workshop keeps", role: .destructive) {
                    confirmingEraseAll = true
                }
            } footer: {
                Text("Walk-throughs and their photos, the tally, the medicine log, what Ingredient watch looks for, standing orders, place notes, skills, and today's notes. Everything here is sealed on this phone. Nothing is sent to an assistant unless you ask for it.")
            }
        }
        .navigationTitle("Workshop")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Erase the medicine log?", isPresented: $confirmingEraseDoses, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { workshop.eraseDoses() }
        } message: {
            Text("Dose guard will not know about any dose logged before now.")
        }
        .confirmationDialog("Erase everything the workshop keeps?", isPresented: $confirmingEraseAll, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) { workshop.eraseEverything() }
        } message: {
            Text("This cannot be undone. That includes what Ingredient watch looks for. Your switches stay as they are.")
        }
    }

    private func row(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(count)")
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ingredients

private struct IngredientListView: View {
    @ObservedObject private var workshop = WorkshopCoordinator.shared
    @State private var word = ""
    @State private var note: String?

    var body: some View {
        Form {
            Section {
                ForEach(Allergen.catalog) { allergen in
                    Toggle(allergen.name.capitalized, isOn: Binding(
                        get: { workshop.watchList.allergens.contains(allergen.id) },
                        set: { workshop.setAllergen(allergen.id, on: $0) }
                    ))
                }
            } footer: {
                Text("For each of these, Phoenix Fox knows the other names it goes by on a label: whey and casein for milk, albumen for egg, and so on. The lists are long, and they are not complete.")
            }

            Section {
                ForEach(workshop.watchList.custom, id: \.self) { item in
                    Text(item)
                }
                .onDelete { offsets in
                    for item in offsets.map({ workshop.watchList.custom[$0] }) { workshop.removeIngredient(item) }
                }
                HStack {
                    TextField("Another word to look for", text: $word)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Your own words")
            } footer: {
                Text("A word you add is matched exactly as you wrote it, and its plural. Phoenix Fox does not know its other names. You can also say \"add coconut to my allergies\". This list is sealed on this phone and never sent anywhere.")
            }
        }
        .navigationTitle("What to look for")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        let wanted = word.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return }
        if let name = workshop.addIngredient(wanted) {
            note = "Added \(name)."
            word = ""
        } else {
            note = "That is already on the list, or the list is full."
        }
        if let note { UIAccessibility.post(notification: .announcement, argument: note) }
    }
}

// MARK: - Walk-throughs

private struct WalkThroughListView: View {
    @ObservedObject private var workshop = WorkshopCoordinator.shared

    var body: some View {
        List {
            ForEach(workshop.walks.reversed()) { walk in
                NavigationLink {
                    WalkThroughView(walk: walk)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(walk.name)
                        Text("\(walk.startedAt.formatted(date: .abbreviated, time: .shortened)), \(walk.spokenCounts)\(walk.finishedAt == nil ? ", still open" : "")")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onDelete { offsets in
                let shown = Array(workshop.walks.reversed())
                for id in offsets.map({ shown[$0].id }) { workshop.removeWalk(id) }
            }
        }
        .navigationTitle("Walk-throughs")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WalkThroughView: View {
    let walk: WalkThrough
    @ObservedObject private var workshop = WorkshopCoordinator.shared

    var body: some View {
        List {
            Section {
                ShareLink(item: workshop.report(for: walk), subject: Text(walk.name)) {
                    Label("Share the report", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("The report is text. Photos stay on this phone unless you send the walk-through to an assistant by voice.")
            }
            Section {
                ForEach(walk.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.text, systemImage: item.kind == .flag ? "flag.fill" : "note.text")
                            .foregroundColor(item.kind == .flag ? .orange : .primary)
                            .accessibilityLabel("\(item.kind == .flag ? "Flag" : "Note"): \(item.text)")
                        Text(item.at.formatted(date: .omitted, time: .shortened))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        if let name = item.photo, let data = workshop.photo(named: name), let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel("Photo taken with this \(item.kind == .flag ? "flag" : "note")")
                        }
                    }
                }
            }
        }
        .navigationTitle(walk.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Place notes

private struct PlaceNoteListView: View {
    @ObservedObject private var workshop = WorkshopCoordinator.shared

    var body: some View {
        List {
            ForEach(workshop.notes.notes.reversed()) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.text)
                    Text("Left \(note.at.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .onDelete { offsets in
                let shown = Array(workshop.notes.notes.reversed())
                for id in offsets.map({ shown[$0].id }) { workshop.removeNote(id) }
            }
        }
        .navigationTitle("Place notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Skills

private struct SkillListView: View {
    @ObservedObject private var workshop = WorkshopCoordinator.shared
    @State private var adding = false

    private var examples: [Skill] {
        Skills.examples.filter { example in !workshop.skills.contains { $0.id == example.id } }
    }

    var body: some View {
        List {
            Section {
                ForEach(workshop.skills) { skill in
                    NavigationLink {
                        SkillView(skill: skill, installed: true)
                    } label: {
                        label(skill)
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ workshop.skills[$0].id }) { workshop.removeSkill(id) }
                }
                Button {
                    adding = true
                } label: {
                    Label("Add a skill from its file", systemImage: "plus")
                }
            } header: {
                Text("Added")
            } footer: {
                Text("Up to \(Skill.limit). Swipe one to remove it.")
            }

            if !examples.isEmpty {
                Section {
                    ForEach(examples) { skill in
                        NavigationLink {
                            SkillView(skill: skill, installed: false)
                        } label: {
                            label(skill)
                        }
                    }
                } header: {
                    Text("Examples")
                } footer: {
                    Text("These come with Phoenix Fox. None is added until you add it.")
                }
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            SkillPasteView()
        }
    }

    private func label(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(skill.name)
            if let phrase = skill.phrases.first {
                Text("\"\(phrase)\"")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Everything a skill does, shown before it is added and afterwards.
private struct SkillView: View {
    let skill: Skill
    let installed: Bool

    @ObservedObject private var workshop = WorkshopCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var problem: String?

    var body: some View {
        Form {
            if let about = skill.about, !about.isEmpty {
                Section {
                    Text(about)
                }
            }
            Section("Say") {
                ForEach(skill.phrases, id: \.self) { phrase in
                    Text(phrase)
                }
            }
            Section {
                ForEach(skill.permissions, id: \.self) { line in
                    Text(line)
                }
            } header: {
                Text("What it does")
            } footer: {
                Text("This is everything the skill can capture. A skill cannot run code, name a web address, or capture anything that is not listed here.")
            }
            Section {
                Text(skill.ask)
                    .font(.callout)
            } header: {
                Text("What it asks \(skill.bot ?? "your assistant")")
            } footer: {
                Text("This is sent to your assistant as if you had said it, and your assistant can do whatever you have let it do.")
            }
            Section {
                if installed {
                    Button("Remove this skill", role: .destructive) {
                        workshop.removeSkill(skill.id)
                        dismiss()
                    }
                } else {
                    Button("Add this skill") {
                        do {
                            try workshop.install(skill)
                            dismiss()
                        } catch {
                            problem = (error as? SkillError)?.message ?? "This skill could not be added."
                        }
                    }
                }
                ShareLink(item: skill.encoded(), subject: Text(skill.name)) {
                    Label("Share the skill file", systemImage: "square.and.arrow.up")
                }
                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle(skill.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Paste a skill file, see what it does, then add it.
private struct SkillPasteView: View {
    @ObservedObject private var workshop = WorkshopCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @State private var file = ""
    @State private var checked: Skill?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $file)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Skill file")
                        .onChange(of: file) { _, _ in
                            checked = nil
                            problem = nil
                        }
                    Button("Paste") {
                        file = UIPasteboard.general.string ?? ""
                    }
                    Button("Check it") {
                        check()
                    }
                    .disabled(file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Skill file")
                } footer: {
                    Text("Paste the text of a skill file. Nothing is added until you have seen what it does.")
                }

                if let problem {
                    Section {
                        Text(problem)
                            .foregroundColor(.red)
                    }
                }

                if let checked {
                    Section {
                        Text(checked.name)
                            .font(.headline)
                        ForEach(checked.phrases, id: \.self) { phrase in
                            Text("Say: \(phrase)")
                        }
                        ForEach(checked.permissions, id: \.self) { line in
                            Text(line)
                        }
                    } header: {
                        Text("What it does")
                    } footer: {
                        Text("This is everything the skill can capture.")
                    }
                    Section {
                        Text(checked.ask)
                            .font(.callout)
                    } header: {
                        Text("What it asks \(checked.bot ?? "your assistant")")
                    } footer: {
                        Text("Read this. It is sent to your assistant as if you had said it, and your assistant can do whatever you have let it do.")
                    }
                    Section {
                        Button(replaces(checked) ? "Replace \(checked.name)" : "Add \(checked.name)") {
                            add(checked)
                        }
                    } footer: {
                        if replaces(checked) {
                            Text("You already have a skill with this id. Adding this one replaces it.")
                        }
                    }
                }
            }
            .navigationTitle("Add a skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func replaces(_ skill: Skill) -> Bool {
        workshop.skills.contains { $0.id == skill.id }
    }

    private func check() {
        do {
            checked = try Skill.decode(file)
            problem = nil
        } catch {
            checked = nil
            problem = (error as? SkillError)?.message ?? "This is not a skill file."
        }
        if let problem { UIAccessibility.post(notification: .announcement, argument: problem) }
    }

    private func add(_ skill: Skill) {
        do {
            try workshop.install(skill)
            dismiss()
        } catch {
            problem = (error as? SkillError)?.message ?? "This skill could not be added."
            if let problem { UIAccessibility.post(notification: .announcement, argument: problem) }
        }
    }
}
