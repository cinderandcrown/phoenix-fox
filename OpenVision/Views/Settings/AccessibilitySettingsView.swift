// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The accessibility suite's settings.
//
// Everything here can also be done by voice. The screen uses only standard controls with
// text labels, so VoiceOver, Switch Control, Voice Control, and large text all work with
// it as they do in the Settings app. Nothing depends on color or on a swipe.

import SwiftUI

struct AccessibilitySettingsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @ObservedObject private var guide = GuideMode.shared
    @ObservedObject private var captions = LiveCaptions.shared
    @ObservedObject private var faces = AccessFaces.shared
    @ObservedObject private var coordinator = AccessibilityCoordinator.shared

    @State private var showingSafetyNotice = false
    @State private var status = ""
    @State private var namesText = ""

    private var settings: Binding<AccessibilitySettings> {
        $settingsManager.settings.accessibility
    }

    var body: some View {
        Form {
            if !status.isEmpty {
                Section {
                    Text(status)
                }
            }
            seeing
            help
            hearing
            speech
            memory
            Section {
                Text(AccessHelp.spoken)
                    .font(.callout)
            } header: {
                Text("By voice")
            } footer: {
                Text("Say \"Hey Phoenix, what can I say?\" to hear this list.")
            }
        }
        .navigationTitle("Accessibility")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            namesText = settingsManager.settings.accessibility.names.joined(separator: ", ")
        }
        .onChange(of: settingsManager.settings.accessibility) {
            AccessibilityCoordinator.shared.apply()
        }
        .alert("Before you use Guide mode", isPresented: $showingSafetyNotice) {
            Button("I understand, start") {
                report(AccessibilityCoordinator.shared.startGuideAfterSafetyNotice())
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(GuideMode.safetyNotice)
        }
    }

    // MARK: - Seeing

    private var seeing: some View {
        Section {
            Toggle("Guide mode", isOn: Binding(
                get: { guide.isOn },
                set: { on in
                    if !on {
                        report(GuideMode.shared.stop())
                    } else if settingsManager.settings.accessibility.guideSafetyAccepted {
                        report(GuideMode.shared.start())
                    } else {
                        showingSafetyNotice = true
                    }
                }
            ))
            .accessibilityHint("Calls out people, vehicles, stairs, doors, and signs through the glasses. The camera light stays on.")
            Toggle("Ask the assistant about hazards", isOn: settings.guideCloudDescriptions)
                .accessibilityHint("When the scene changes, one picture may go to the assistant to check for hazards the phone can't detect.")
            Toggle("Direction tones", isOn: settings.guideAudioCues)
                .accessibilityHint("A falling tone means left, a rising tone means right, and a level tone means ahead.")
            Toggle("Face recognition", isOn: settings.faceRecognition)
                .accessibilityHint("Recognizes only people you have saved with their permission.")
            NavigationLink {
                SavedFacesView()
            } label: {
                LabeledContent("Saved faces", value: "\(faces.records.count)")
            }
        } header: {
            Text("Seeing")
        } footer: {
            Text("Guide mode is an aid. It misses things, especially curbs, drop-offs, glass, and fast traffic. It does not replace a cane, a guide dog, or your own judgment. Reading, colors, money, labels, and faces are worked out on this phone. Face data never leaves it.")
        }
    }

    // MARK: - Getting help

    private var help: some View {
        Section {
            TextField("Name", text: settings.emergencyContactName)
                .textContentType(.name)
                .accessibilityLabel("Emergency contact name")
            TextField("Phone number", text: settings.emergencyContactNumber)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .accessibilityLabel("Emergency contact phone number")
        } header: {
            Text("Emergency contact")
        } footer: {
            Text("Say \"Hey Phoenix, call my emergency contact\". Phoenix Fox asks you to confirm, then starts the call. iPhone shows a Call button that has to be tapped, so if you can't reach the phone, say \"Hey Meta, call\" and the name.")
        }
    }

    // MARK: - Hearing

    private var hearing: some View {
        Section {
            Toggle("Live captions", isOn: Binding(
                get: { captions.isOn },
                set: { on in report(on ? LiveCaptions.shared.start() : LiveCaptions.shared.stop()) }
            ))
            NavigationLink("Captions and transcripts") {
                LiveCaptionsView()
            }
            Toggle("Keep captions after they stop", isOn: settings.keepTranscripts)
                .accessibilityHint("Keeps the lines on the captions screen so you can save them. Off clears them when captions stop.")
            Toggle("Sound alerts", isOn: settings.soundAlerts)
                .accessibilityHint("Shows an alert and vibrates the phone for sirens, alarms, the doorbell, and other sounds.")
            NavigationLink {
                SoundKindsView()
            } label: {
                LabeledContent("Sounds to listen for", value: "\(settingsManager.settings.accessibility.soundKinds.count)")
            }
            Toggle("Also say alerts aloud", isOn: settings.speakSoundAlerts)
            TextField("Your names, separated by commas", text: $namesText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .accessibilityLabel("Names to listen for")
                .onChange(of: namesText) {
                    settingsManager.settings.accessibility.names = namesText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
        } header: {
            Text("Hearing")
        } footer: {
            Text("Captions and sound alerts work while Phoenix Fox is listening for the wake word. Sounds are recognized on this phone and are never recorded. When someone says one of your names while captions are on, the phone vibrates and shows an alert. Captions can't tell speakers apart, and they include your own voice.")
        }
    }

    // MARK: - Speech and movement

    private var speech: some View {
        Section {
            Picker("Speaking speed", selection: settings.pace) {
                Text("Slower").tag(SpeechPace.slow)
                Text("Normal").tag(SpeechPace.normal)
                Text("Faster").tag(SpeechPace.fast)
            }
            Toggle("Give me more time to speak", isOn: settings.extraTime)
                .accessibilityHint("Waits longer through pauses before acting on what you said.")
        } header: {
            Text("Speech and movement")
        } footer: {
            Text("Every feature works by voice alone. Anything that calls someone, saves a face, or deletes several things asks first, and a single yes or no is enough. Slower and faster speech use the built-in voice.")
        }
    }

    // MARK: - Memory and tasks

    private var memory: some View {
        Section {
            NavigationLink {
                RoutinesView()
            } label: {
                LabeledContent("Routines", value: "\(coordinator.routines.count)")
            }
            NavigationLink {
                PersonRemindersView()
            } label: {
                LabeledContent("Reminders for people", value: "\(coordinator.reminders.count)")
            }
            Toggle("Activity recall", isOn: settings.activityRecall)
                .accessibilityHint("Keeps a short list of the tasks, walks, and reading you start, so you can ask what you were doing.")
        } header: {
            Text("Memory and tasks")
        } footer: {
            Text("Activity recall keeps one line for each thing you start with Phoenix Fox, for one day, sealed on this phone. It is not a recording. Turning it off erases the list.")
        }
    }

    /// Shows a result on the screen and reads it out for VoiceOver.
    private func report(_ line: String) {
        status = line
        AccessibilityNotification.Announcement(line).post()
    }
}

// MARK: - Saved faces

private struct SavedFacesView: View {
    @ObservedObject private var faces = AccessFaces.shared
    @State private var confirmingDeleteAll = false

    var body: some View {
        List {
            if faces.records.isEmpty {
                Text("No one is saved. With the person's permission, say \"Hey Phoenix, remember this person as\" and their name while you face them.")
            }
            ForEach(faces.records) { record in
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.name)
                        .font(.headline)
                    Text("Agreed on \(record.consentAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Delete \(record.name)", role: .destructive) {
                        _ = AccessFaces.shared.forget(name: record.name)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
            if !faces.records.isEmpty {
                Section {
                    Button("Delete all saved faces", role: .destructive) {
                        confirmingDeleteAll = true
                    }
                } footer: {
                    Text("Face data is a set of numbers made from a picture. No picture is kept. It is sealed on this phone, is not in backups, and is never sent anywhere.")
                }
            }
        }
        .navigationTitle("Saved faces")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete every saved face?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) { _ = AccessFaces.shared.forgetAll() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Sounds

private struct SoundKindsView: View {
    @EnvironmentObject private var settingsManager: SettingsManager

    var body: some View {
        List {
            Section {
                ForEach(SoundKind.allCases, id: \.self) { kind in
                    Toggle(kind.title, isOn: Binding(
                        get: { settingsManager.settings.accessibility.soundKinds.contains(kind) },
                        set: { on in
                            if on {
                                settingsManager.settings.accessibility.soundKinds.insert(kind)
                            } else {
                                settingsManager.settings.accessibility.soundKinds.remove(kind)
                            }
                            AccessibilityCoordinator.shared.apply()
                        }
                    ))
                }
            } footer: {
                Text("Recognition is not perfect. Do not rely on it where a missed alarm could put you in danger. Keep the alerting devices you already use.")
            }
        }
        .navigationTitle("Sounds to listen for")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Routines

private struct RoutinesView: View {
    @ObservedObject private var coordinator = AccessibilityCoordinator.shared
    @State private var name = ""
    @State private var steps = ""

    private var parsedSteps: [String] { Routine.steps(from: steps) }

    var body: some View {
        Form {
            Section {
                TextField("Name, such as Morning", text: $name)
                    .accessibilityLabel("Routine name")
                TextField("Steps, one on each line", text: $steps, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityLabel("Steps, one on each line")
                Button("Save routine") {
                    let title = name.trimmingCharacters(in: .whitespaces)
                    coordinator.saveRoutine(Routine(name: title, steps: parsedSteps))
                    let saved: String = "Saved \(title), \(parsedSteps.count) steps."
                    AccessibilityNotification.Announcement(saved).post()
                    name = ""
                    steps = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedSteps.isEmpty)
            } header: {
                Text("New routine")
            } footer: {
                Text("Start one by saying \"Hey Phoenix, start my morning routine\". Phoenix Fox says one step, then waits for \"next\", \"back\", or \"repeat\".")
            }
            ForEach(coordinator.routines) { routine in
                Section(routine.name) {
                    ForEach(Array(routine.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                    Button("Delete \(routine.name)", role: .destructive) {
                        coordinator.removeRoutine(routine)
                    }
                }
            }
        }
        .navigationTitle("Routines")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reminders for people

private struct PersonRemindersView: View {
    @ObservedObject private var coordinator = AccessibilityCoordinator.shared

    var body: some View {
        List {
            if coordinator.reminders.isEmpty {
                Text("None waiting. Say \"Hey Phoenix, when I see Sam, remind me to return the keys\". It is said when Phoenix Fox recognizes that person, so their face must be saved and face recognition must be on.")
            }
            ForEach(Array(coordinator.reminders.enumerated()), id: \.offset) { _, reminder in
                VStack(alignment: .leading, spacing: 6) {
                    Text("When I see \(reminder.person)")
                        .font(.headline)
                    Text(reminder.note)
                    Button("Delete this reminder", role: .destructive) {
                        coordinator.removeReminder(reminder)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Reminders for people")
        .navigationBarTitleDisplayMode(.inline)
    }
}
