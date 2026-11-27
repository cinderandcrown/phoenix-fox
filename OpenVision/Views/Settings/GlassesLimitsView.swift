// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

// The switches for what Phoenix Fox asks of the glasses beyond the basics. Shown only in
// the owner build, because most of these use parts of Meta's toolkit that Meta still
// calls beta. Every switch says what it costs as well as what it gives.

import SwiftUI

struct GlassesLimitsView: View {
    @EnvironmentObject var settingsManager: SettingsManager

    @State private var microphoneNote: String?

    var body: some View {
        Form {
            Section {
                Toggle("Full-rate video", isOn: $settingsManager.settings.glasses.fullRateVideo)
                    .accessibilityHint("Uses the sharpest and smoothest stream each feature can use, up to 720 by 1280 at 30 frames a second.")
                Toggle("Photos from the whole sensor", isOn: $settingsManager.settings.glasses.highResolutionStills)
                    .accessibilityHint("Saved pictures and pages to read are taken at up to 4032 by 3024.")
                Toggle("Sound from the glasses", isOn: $settingsManager.settings.glasses.ambientAudio)
                    .accessibilityHint("While the camera is on, recordings and sound alerts hear the room through the glasses microphones.")
            } header: {
                Text("Camera")
            } footer: {
                Text("Full-rate video asks for up to 720 by 1280 at 30 frames a second for a recording, and less for features that need less. Off, every stream is 504 by 896 at 7 frames a second. Whole-sensor photos are up to 4032 by 3024 and take a few seconds each. All of it uses more of the glasses' battery, and the stream steps down by itself when the glasses get warm. The capture light is on whenever the camera is.")
            }

            Section {
                Toggle("Touchpad and action button", isOn: $settingsManager.settings.glasses.controls)
                    .accessibilityHint("A double tap talks to Phoenix. A swipe back stops Phoenix talking.")
                Toggle("Capture button", isOn: $settingsManager.settings.glasses.captureButton)
                    .accessibilityHint("One press looks, two presses keep a picture, and holding it takes a note.")
                Toggle("Nod and shake", isOn: $settingsManager.settings.glasses.headGestures)
                    .accessibilityHint("A shake of the head answers no or stops Phoenix talking. Two nods answer yes to some questions.")
            } header: {
                Text("Controls")
            } footer: {
                Text("These work while Phoenix is busy with you: from the wake word until about twenty seconds after the answer, and for as long as the camera is on. In that time a double tap on the touchpad talks to Phoenix, a swipe back stops it talking, and the capture button looks with one press, keeps a picture with two, and takes a note when held. A shake of the head says no, or stops Phoenix talking. Two nods say yes, but only to questions about your own lists. A yes that calls someone, saves or erases a face, starts Guide mode, or lets an assistant act must be spoken.\n\nWhile they work, the glasses keep two gestures for themselves: a single tap pauses Phoenix Fox's connection and a long press ends it. The rest of the time the glasses behave as they always do.")
            }

            Section {
                Toggle("Speech on the glasses", isOn: speechSwitch)
                    .accessibilityHint("When the phone's microphone is not listening, the glasses listen for the wake word instead.")
                if settingsManager.settings.glasses.onGlassesSpeech {
                    Button("Allow the glasses' microphone") {
                        askForMicrophone()
                    }
                    .accessibilityHint("Opens the Meta AI app to ask.")
                }
                if let microphoneNote {
                    Text(microphoneNote)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("A second ear")
            } footer: {
                Text("When the phone's microphone is not listening, the glasses turn speech into text themselves. Phoenix Fox acts only on a sentence that starts with the wake word, and the wake word alone starts the phone listening again. Nothing the glasses hear is kept.\n\nThis is the one switch that changes the glasses when Phoenix is not busy: for as long as the phone is not listening, a single tap on the touchpad pauses Phoenix Fox's connection and a long press ends it, in place of what they normally do. It needs the glasses' microphone, which the Meta AI app asks you to allow. In this build the switch starts on, so use the button once.")
            }

            Section {
                Button("Turn everything on again") {
                    settingsManager.applyOwnerProfile()
                }
            } footer: {
                Text("\(BuildFlavor.current.label). Every feature starts switched on in this build, and anything you switch off stays off. This button switches all of it back on. It does not start the camera, a recording, or Guide mode, and it does not skip the Guide mode safety notice or the consent question for saving a face.")
            }
        }
        .navigationTitle("Glasses limits")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Turning the switch on asks for the glasses' microphone, which the Meta AI app shows.
    private var speechSwitch: Binding<Bool> {
        Binding(
            get: { settingsManager.settings.glasses.onGlassesSpeech },
            set: { on in
                settingsManager.settings.glasses.onGlassesSpeech = on
                microphoneNote = nil
                if on { askForMicrophone() }
            }
        )
    }

    private func askForMicrophone() {
        Task { @MainActor in
            let granted = await GlassesControlSession.shared.requestSpeechPermission()
            microphoneNote = granted
                ? "The glasses' microphone is allowed."
                : "The glasses' microphone is not allowed yet. Connect the glasses and ask again."
        }
    }
}

#Preview {
    NavigationStack {
        GlassesLimitsView()
            .environmentObject(SettingsManager.shared)
    }
}
