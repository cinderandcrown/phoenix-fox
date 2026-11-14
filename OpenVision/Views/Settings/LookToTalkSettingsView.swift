// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// Look to Talk's own screen: its switch, what happens when a window is found, the names
// a window may show, and a badge and a marker for each assistant. Shown only in the
// owner build, from the Workshop.

import SwiftUI

struct LookToTalkSettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @ObservedObject private var look = LookToTalk.shared

    private var settings: Binding<WorkshopSettings> { $settingsManager.settings.workshop }
    private var bots: [AssistantBot] { AssistantRoster.normalized(settingsManager.settings.assistantBots) }
    private var isOn: Bool { settingsManager.settings.workshop.lookToTalk }

    var body: some View {
        Form {
            Section {
                Toggle("Look to Talk", isOn: settings.lookToTalk)
                    .accessibilityHint("Say look to talk, then look at an assistant's chat window.")
                    .onChange(of: isOn) { _, on in
                        if !on { look.stop() }
                    }
                if look.status != .off {
                    HStack {
                        Label(look.status.title, systemImage: look.status.symbol)
                        Spacer()
                        Button("Let go") { look.stop() }
                    }
                }
            } footer: {
                Text("Say \"look to talk\" and look at an assistant's chat window on your computer. The glasses camera comes on, with its light, and the phone reads the screen for the assistant's name. When it finds one you hear a tone and the name, and what you say next goes to that assistant without saying its name again.\n\nThe pictures are read on this phone and thrown away. None is saved and none is sent anywhere. The camera goes off as soon as an assistant is locked on, and after 45 seconds if no window is found.")
            }

            Section {
                Toggle("Lock on, and turn the camera off", isOn: settings.lookAutoLock)
                    .accessibilityHint("When off, the assistant is held only while its window stays in view, and the camera stays on.")
                Toggle("Listen for my request after the tone", isOn: settings.lookListenAfterTone)
                    .accessibilityHint("Opens the microphone for one sentence, as the wake word would.")
                Stepper(value: settings.lookLockMinutes, in: WorkshopSettings.lockRange, step: 1) {
                    Text("Let go after \(Int(settingsManager.settings.workshop.lookLockMinutes)) minutes unused")
                }
            } header: {
                Text("When a window is found")
            } footer: {
                Text("A lock that is not used ends by itself, so that something you say an hour later does not go to an assistant you chose for something else. Each request sent to the assistant starts the count again.")
            }
            .disabled(!isOn)

            Section {
                ForEach(bots) { bot in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bot.name)
                            .font(.subheadline.weight(.semibold))
                        TextField("Other names, with commas between", text: otherNames(for: bot))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Other names \(bot.name)'s window may show")
                    }
                }
            } header: {
                Text("Names on the screen")
            } footer: {
                Text("If an assistant's chat window shows a different name, such as the handle its chat app uses, add it here. A name is matched when it stands alone on a line or in a short one, like a window's title. A name inside a sentence is not enough.")
            }

            Section {
                ForEach(bots) { bot in
                    NavigationLink {
                        LookBadgeView(name: bot.name)
                    } label: {
                        Text("Badge and marker for \(bot.name)")
                    }
                }
            } header: {
                Text("Badges and markers")
            } footer: {
                Text("A window's title is small, and the glasses camera may not be able to read it from where you sit. A badge is the words TALK TO and the name, in large letters, shown beside the window. A marker is a small square code that says the same thing. Either one is found in a single look.")
            }

            Section {
                ForEach(Self.phrases, id: \.say) { phrase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\"\(phrase.say)\"")
                        Text(phrase.does)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("What to say")
            } footer: {
                Text("When Phoenix Fox is not sure, it asks: \"Talking to Indy?\" Say yes, no, or the right name. A nod or a shake of the head also answers. While an assistant is held, saying another's name still works: \"ask Driver to check the gate\" goes to Driver.\n\nThis is new and has not been tried on glasses yet. See docs/LOOK_TO_TALK.md for what is known and what is not.")
            }
        }
        .navigationTitle("Look to Talk")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func otherNames(for bot: AssistantBot) -> Binding<String> {
        Binding(
            get: { settingsManager.settings.workshop.lookOtherNames[bot.id] ?? "" },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                settingsManager.settings.workshop.lookOtherNames[bot.id] = trimmed.isEmpty ? nil : text
            }
        )
    }

    private struct Phrase {
        var say: String
        var does: String
    }

    private static let phrases: [Phrase] = [
        Phrase(say: "Look to talk", does: "Turns the camera on and looks for an assistant's window."),
        Phrase(say: "Lock on", does: "Keeps the assistant in view, so you can look away."),
        Phrase(say: "Lock on to Indy", does: "Chooses an assistant by name, without the camera."),
        Phrase(say: "Look again", does: "Looks for another window. The lock is kept until one is found."),
        Phrase(say: "Who am I talking to?", does: "Says which assistant is held."),
        Phrase(say: "Let go", does: "Lets go of the assistant and turns the camera off."),
        Phrase(say: "Ask this one to check the build", does: "Takes one look and sends one request, without locking on."),
        Phrase(say: "Look at this", does: "While an assistant is held, sends it a photo of what you are looking at."),
    ]
}

/// A badge and a marker for one assistant, to put on the screen beside its window.
struct LookBadgeView: View {
    let name: String

    private var marker: UIImage? { LookBadgeImage.marker(for: name) }
    private var shareTitle: String { "Look to Talk marker for \(name)" }

    var body: some View {
        Form {
            Section {
                // Black on white whatever the phone's appearance: this is read by a camera.
                Text("TALK TO \(name.uppercased())")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(Color.white)
                    .accessibilityLabel("Badge: talk to \(name)")
            } header: {
                Text("Badge")
            } footer: {
                Text("Type these words in large letters where they will show beside \(name)'s window: a sticky note on the desktop, the name of the browser tab, or a paper label under the screen. Letters about two centimetres tall can be read from across a desk.")
            }

            Section {
                if let marker {
                    Image(uiImage: marker)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .accessibilityLabel("Marker code for \(name)")
                    ShareLink(item: Image(uiImage: marker), preview: SharePreview(shareTitle, image: Image(uiImage: marker))) {
                        Label("Share the marker", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Text("A marker needs a name with letters or digits in it.")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Marker")
            } footer: {
                if let payload = LookMarker.payload(for: name) {
                    Text("Send this picture to your computer and keep it open beside \(name)'s window, about four centimetres across or larger. Any QR code with the text \(payload) works the same way.")
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
