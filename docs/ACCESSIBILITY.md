# Accessibility

Phoenix Fox has an accessibility suite for people who are blind or have low vision, who are Deaf or hard of hearing, who have a speech or motor disability, or who want help with memory and multi-step tasks. Everything in it works by voice through the glasses, and everything can also be set on the iPhone under Settings, then Accessibility, with VoiceOver.

Most of it runs on the phone. Reading, money, labels, colors, faces, sound alerts, task guidance, and recall need no signal and cost nothing to use.

Accessibility is **presence under constraint**: timely callouts, interruptible speech, shared memory of what was just read, and no spam. Every row must satisfy the [presence checklist](DESIGN_PRINCIPLES.md#presence-checklist-every-feature) in [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md) — especially Interrupt respect, quiet periods, and on-device triggers.

## Safety

Read this before relying on any of it.

- **Guide mode is an aid.** It misses things, especially curbs, drop-offs, glass, and fast traffic. It does not replace a cane, a guide dog, orientation and mobility training, or your own judgment. It never says that a road is safe to cross. The app says this aloud and asks for a yes the first time Guide mode is started.
- **Walking directions follow the map, not the pavement.** They cannot see crossings, roadworks, or obstacles.
- **Medicine labels are read, not interpreted.** The app speaks only the words printed on the label and never gives advice about a dose. A strength or direction the camera did not read clearly is left out, and the app says part of the label was hard to read. Check with a pharmacist or someone you trust.
- **Sound alerts and captions make mistakes.** Do not rely on them where a missed alarm or a misheard word could put you in danger. Keep the alerting devices you already use.
- **The emergency call needs one tap.** iOS does not let an app place a call by itself. It shows a Call button first. If you cannot reach the phone, say "Hey Meta, call" and the name.
- **Phoenix Fox is not a medical device.**

## Status

Nothing in this table has been run on a pair of glasses yet. The words mean:

- **Written**: the whole path is in the app. Its decisions are covered by unit tests, and the code that joins them to the phone was type-checked under strict concurrency against stand-ins for Apple's frameworks. It has not yet been built by Xcode in CI or run on the glasses. A row moves to Built when CI builds it, and to Done when the owner has seen it work **and** its presence checklist is filled.
- **Partial**: a real part is written, and the last column names what is missing.
- **Blocked**: Meta or iOS does not allow it.
- **Not started**: asked for or planned, and not written.

### Presence checklist (each accessibility feature)

- Shared experience; live follow-ups (“more”, “again”) without re-waking; memory of the open document / last label; context where safe; proactive callouts only when on-device-triggered, Interrupt-aware, tunable, and quiet-period gated; consistent Phoenix voice; privacy; honest limits. Full list: [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md#presence-checklist-every-feature).

### Blind and low vision

| Feature | Status | Notes and what remains |
| --- | --- | --- |
| Read text and documents | Written | "Read this." Read on the phone in reading order, a paragraph at a time, with "more", "back", and "again". Columns are kept apart. No help with framing the page yet beyond a spoken hint when no text is found. Handwriting is not handled. In the owner build the page is photographed from the whole sensor, which makes small print legible, and falls back to a video frame if that photo does not arrive. |
| Read a sign | Written | "Read the sign." Speaks only the largest text in view. |
| Medicine and other labels | Written | "Read the label." Name and strength, directions, expiry, then warnings, in the label's own words. Falls back to plain reading when it is not a medicine label. No barcode lookup. Uses the same whole-sensor photo in the owner build. |
| Money | Written | "What bill is this?" US dollars, euros, British pounds, and Canadian dollars, from the words and numbers printed on the note. It answers only when one value clearly wins. Coins are refused. Other currencies are not started. |
| Color | Written | "What color is this?" Names the middle of the picture with everyday clothing words, and a second color for stripes or prints. Says when the light is too low to be sure. |
| Describe the scene | Written | "Describe the scene." The on-device vision model when it is loaded, the cloud model when a key is set, and a plain list from the phone's own detectors when neither is there. |
| Find something | Written | "Where's the door?" The phone's detectors first, then a model. A model's answer about position is spoken as a guess. No continuous tone that guides you toward the object yet. |
| Guide mode | Written | "Start guide mode." Calls out people, vehicles, stairs, doors, animals, and large signs about once a second, with a direction tone before each. Urgent callouts interrupt, the rest wait for quiet. Curbs and drop-offs are not detected reliably from one camera, and the app says so. No distance in feet or meters. |
| Face recognition, with consent | Written | Off until turned on. "Remember this person as Sam" asks whether Sam has agreed, and saves only after a yes. One face in view is required. "Who is this?", "forget Sam's face", "forget all faces". |
| Walking directions | Written | "Walk me to the pharmacy." Apple Maps plans the route. Each turn is spoken ahead of time and again at the turn, with re-routing when you leave the route. Starting from a locked phone needs location set to Always. |
| Where am I | Written | Nearest street address. |
| Emergency contact | Written | "Call my emergency contact" asks for a yes, then opens the iOS call prompt. See Safety. |
| Volunteer or professional video help | Blocked | Be My Eyes on the glasses is part of Meta AI, and a third-party app cannot join it. Aira has its own app for these glasses. Phoenix Fox says so and offers a description. |

### Deaf and hard of hearing

| Feature | Status | Notes and what remains |
| --- | --- | --- |
| Live captions on the iPhone | Written | "Start captions." Large text on the main screen and a captions screen. Kept on the phone when the phone can recognize speech by itself, and the app says which it is. They run while Phoenix Fox waits for the wake word. They cannot tell speakers apart, and they include your own voice. |
| Live captions on the lens | Partial | The lens code is written and runs only when the glasses report a display. It has never run on Display glasses. Adventurer has no display. |
| Sound alerts | Written | Sirens, smoke alarms, doorbell, knocking, car horn, baby crying, dog barking, phone ringing, alarm clock, glass breaking, shouting, appliance beeps, running water. Each can be turned off. A banner, a vibration, and a notification, which a paired Apple Watch taps out. A sound must hold for two windows in a row, and each kind has a quiet period so it does not repeat. The glasses microphone reaches the phone as 8 kHz audio, which may hide high-pitched alarms. In the owner build, while the camera is on, the alerts listen to the room through the glasses' own microphones at 16 kHz in its place. Both need testing on the glasses. Custom sounds are not started. |
| Your name called | Written | With captions on, the phone vibrates and shows an alert when someone says one of the names you entered. It depends on the recognizer hearing the name. |
| Conversation transcripts | Written | "What did they say?" reads back the last half minute. "Save this conversation" keeps the transcript, sealed on the phone, where it can be shared or deleted. |
| Typed replies spoken aloud | Not started | |

### Speech and motor

| Feature | Status | Notes and what remains |
| --- | --- | --- |
| Voice-only control | Written | Every feature here has a spoken command, and "what can I say?" lists them. |
| Simple confirm phrases | Written | Anything that calls someone, saves a face, or deletes several things asks first. One short "yes", "no", or "what?" answers. A long sentence is never taken as a yes. An unanswered question lapses. |
| More time to speak | Written | "Give me more time." The app waits two seconds longer through a pause inside a sentence and two and a half times longer for a command or a follow-up. |
| Speaking speed | Written | "Speak slower", "speak faster". Uses the built-in voice, because the neural voices have one speed. |
| Atypical speech | Not started | Recognition is Apple's recognizer and on-device Whisper, with no personal adaptation. |
| Personal command phrases | Not started | |
| Answering without speaking | Written, owner build | With **Nod and shake** on, a shake of the head says no to any question Phoenix is waiting on, and stops Phoenix talking when no question is waiting (not during Guide mode or a walk, where the head turns to look around). Two nods say yes only to a question about your own lists: setting the emergency contact or deleting a routine. A yes that calls someone, saves or erases a face, starts Guide mode, or lets an assistant act must still be spoken. It works from the wake word until about twenty seconds after the answer. |
| Touchpad, buttons, and Neural Band | Partial | In the owner build the touchpad's double tap, a swipe back, and the capture button enter the same turn as speech through `GestureMap`, while Phoenix is busy with you. No gesture is mapped to "next step" yet. The band is listened for only on display glasses and cannot be tested on Adventurer. |
| iPhone screens with VoiceOver, Voice Control, Switch Control | Partial | The Accessibility and Captions screens use standard controls with labels and hints, and nothing depends on color or on a swipe. The home screen and first run were written for VoiceOver, Dynamic Type, Reduce Motion, Increase Contrast, and light and dark mode, with contrast held by tests; [DESIGN.md](DESIGN.md) has the decisions. None of it has been tried with VoiceOver on a phone yet. The other Settings screens and History are system lists and have not had a full pass. |

### Memory and tasks

| Feature | Status | Notes and what remains |
| --- | --- | --- |
| Step-by-step task guidance | Written | "Start my morning routine." One step at a time. "Next", "back", "repeat", "what step am I on", "stop the task". After four quiet minutes it says the step again. The run survives the app closing. The app never judges from the camera whether a step was done. |
| Routines | Written | Taught by voice ("new routine called morning, the steps are …") or typed on the phone by the wearer or a supporter. With no saved routine, the assistant can suggest steps, and the app says they are a suggestion. |
| Reminders tied to a person | Written | "When I see Sam, remind me to return the keys." Spoken when Sam is recognized, so it needs face recognition and Sam's saved face. |
| Reminders tied to a place | Partial | Already in the app as "when I arrive at the office, remind me to …". Arriving with the app in the background needs location set to Always. See [FEATURE_PARITY.md](FEATURE_PARITY.md). |
| "What was I doing?" | Written | Says the task, walk, Guide mode, or captions in progress, then the last few things started in the past two hours. Off until "turn on activity recall". Kept for one day. It is a short list of lines, not a recording. |
| "Where did I put it?" | Not started | |
| A simplified screen with a few large actions | Not started | |

## What to say

Say "Hey Phoenix" first, or speak inside the few seconds after a reply.

| To do this | Say |
| --- | --- |
| Read | "Read this", "read the sign", "read the label", then "more", "back", "again" |
| Identify | "What bill is this?", "what color is this?", "describe the scene", "where's the door?" |
| People | "Turn on face recognition", "remember this person as Sam", "who is this?", "forget Sam's face", "forget all faces" |
| Get around | "Start guide mode", "stop guide mode", "walk me to the pharmacy", "next turn", "stop directions", "where am I?" |
| Get help | "Set my emergency contact to Sam", "call my emergency contact" |
| Hear | "Start captions", "stop captions", "what did they say?", "save this conversation", "clear the captions", "turn on sound alerts" |
| Speak at your pace | "Give me more time", "normal timing", "speak slower", "speak faster", "normal speed" |
| Tasks | "New routine called morning, the steps are …", "start my morning routine", "next", "back", "repeat", "stop the task", "list my routines" |
| Remember | "When I see Sam, remind me to …", "turn on activity recall", "what was I doing?", "forget what I was doing" |
| Learn the commands | "What can I say?" |

A bare "stop" silences speech. It does not end a task or turn Guide mode off.

## How it works

A spoken sentence is offered to the accessibility suite before the general stop handling and before any bot. If it is one of the suite's commands, the phone does the work and speaks the answer. Otherwise the sentence goes on as before.

| Part | Where | What it does |
| --- | --- | --- |
| Decisions | `OpenVision/Services/Accessibility/Core/` | Pure Swift with no Apple frameworks: the command parser, confirmation, reading order, color names, banknotes, medicine labels, Guide callouts, cue tones, route progress, sound-alert policy, captions, task runs, recall, and the face ledger. Unit-tested in `OpenVisionTests/Access*Tests.swift`. |
| The turn | `AccessibilityCoordinator.swift` | Runs one command, holds what is being read and the task in progress, and asks for confirmation. |
| Eyes | `AccessVision.swift`, `AccessFaces.swift` | Apple Vision for text, people, animals, scene labels, and face prints. |
| Guide | `GuideMode.swift`, `WalkingGuide.swift` | The callout loop over the camera stream, and Apple Maps directions over location updates. |
| Ears | `LiveCaptions.swift`, `SoundAlertService.swift` | Captions from the recognizer that already listens for the wake word, and Apple SoundAnalysis on the same microphone tap. No second audio engine is opened. |
| Storage | `AccessStore.swift` | AES-GCM files under a Keychain key that never leaves the device. |

Three rules shape the design.

**Read, do not describe, anything with numbers.** Text, labels, and money go through character recognition and fixed rules, and never through a generative model. A model is used only for scene descriptions and for finding things the phone's detectors missed, and what it says about position is spoken as a guess.

**Unprompted speech does not open a conversation.** A Guide callout or a sound alert is not a reply. If it reopened the microphone for a follow-up, the next thing a passer-by said would be taken as a command. Guide mode also keeps its own camera state for this reason.

**The camera light is the truth.** Guide mode keeps the glasses camera and its light on, says so when it starts, and shows it on the phone. A single reading takes one picture and turns the camera off.

To keep cost low, Guide mode skips frames that look like the last one, uses the phone's detectors for every callout, and asks a model only on a real change of scene, at most once every twelve seconds and sixty times a session. That check can be turned off.

## Privacy and consent

- **Faces.** Off by default. A face is saved only after the wearer confirms aloud that the person agreed, and the time of that answer is stored with it. What is kept is a set of numbers made from the picture. The picture is not kept. Face data is sealed on the phone, is left out of backups, and is never sent anywhere. Any face, or all of them, can be deleted by voice or on the phone. The earlier face store, which was a plain file with no consent record, is deleted on first launch.
- **Captions.** Lines are kept only while captions are on, unless the wearer chooses to keep them or says "save this conversation". Saved transcripts are sealed on the phone. A transcript holds other people's words, and the app says to ask them before sharing it. When the phone cannot recognize speech by itself, Apple's speech service is used, and the app says so when captions start.
- **Sounds.** Audio is classified on the phone as it arrives. Nothing is recorded or sent.
- **Activity recall.** Off by default. One line for each thing started, for one day. Turning it off erases the list.
- **Location.** Used for walking directions and "where am I", and shown by the iOS location arrow while a walk runs.
- **Cloud models.** Only a scene description, a "find" the phone could not answer, Guide mode's hazard check, and suggested task steps can reach a cloud model, and only when a key is set. The on-device model is used first when it is loaded.
- **Other people.** Guide mode and face recognition look at people who did not choose to be looked at. The capture light is on whenever the camera is, and the app does nothing to hide or dim it.

## What existing tools and research taught us

Each source below was opened and checked for the point it is cited for.

| Source | What it shows | What Phoenix Fox does with it |
| --- | --- | --- |
| [Meta, "Advancing accessibility"](https://about.fb.com/news/2025/05/advancing-accessibility-meta/) | Meta AI has a detailed-responses setting and "Call a Volunteer" with Be My Eyes. | The volunteer call cannot be reached from a third-party app, so that row is Blocked. The emergency contact is our human fallback. |
| [Meta, accessibility training for the glasses](https://www.meta.com/actions/ai-glasses-veteran-accessibility-training/) | The glasses are "not a substitute for primary mobility aids like a white cane or guide dog". Trainers teach holding an object 8 to 12 inches from the chin, slightly to the left, because the camera is in the corner of the frame. | The Guide mode notice. The spoken hints when nothing is found tell the wearer how to hold the thing. |
| [Apple, Magnifier Detection Mode](https://support.apple.com/guide/iphone/detect-doors-people-and-furniture-around-you-iph35c335575/ios) | Detects doors, people, and furniture with sounds, speech, and haptics, and warns that it should not be relied on "for navigation". | Guide mode is described as an aid everywhere it appears. Distance-coded feedback is on the list below. |
| [Microsoft Seeing AI](https://blogs.microsoft.com/accessibility/seeing-ai-app-launches-on-android-including-new-and-updated-features-and-new-languages/) | Separate channels for short text, documents, products, currency, colors, and light, some guided by beeps. | A separate command and a separate reader for each task, not one "look and tell me" prompt. |
| [Envision glasses updates](https://www.letsenvision.com/updates/glasses) | Text scanning uses character recognition, which "won't make up content", unlike a general description. | Reading never goes through a generative model. |
| [Aira on AI glasses from Meta](https://aira.io/aira-now-works-with-ai-glasses-from-meta/) | A professional interpreter can see the glasses video through Aira's own app. | We point to it and do not imitate it. |
| [Google Lookout](https://support.google.com/accessibility/android/answer/9031274?hl=en) | Says when no text is detected, and reads food labels offline. | "I don't see any text", with how to hold it. Labels are read offline. |
| [WorldScribe (UIST 2024)](https://arxiv.org/abs/2408.06627) | Live descriptions should be short while the scene is changing and fuller when it is still, and should give way to other sound. | Guide callouts are a few words from the phone's detectors, and the slower model check runs only on a scene change. Non-urgent callouts wait while the wearer is speaking. |
| [VizWiz long-form answers](https://arxiv.org/abs/2408.06303) | Models often invent details for blurry or unanswerable photos and rarely decline. | The model is told to say when it is not sure. The money and label readers treat "I can't tell" as a correct answer. |
| [Preferences for scene descriptions (2025)](https://arxiv.org/abs/2502.14883) | Eight blind and low-vision participants varied widely in how much detail they wanted. | Scene descriptions are short and on request. A verbosity setting is on the list below. |
| [ObjectFinder (2024)](https://arxiv.org/abs/2412.03118) | Blind participants preferred an interactive finder to description apps for locating objects. | "Find" is its own command. A continuous finder is on the list below. |
| [Apple, Sound Recognition](https://support.apple.com/guide/iphone/use-sound-recognition-iphf2dc33312/ios) | iPhone listens for sounds such as a doorbell or siren, can learn a custom alarm, and warns not to rely on it in high-risk situations. | The same warning, in the app and here. Custom sounds are on the list below. |
| [Apple, SoundAnalysis (WWDC21)](https://developer.apple.com/videos/play/wwdc2021/10036/) | A sound classifier is built into iOS. | Sound alerts use it, so no model is bundled and no audio leaves the phone. |
| [Meta Wearables Device Access Toolkit](https://wearables.developer.meta.com/docs/develop/dat/build-overview/) | The glasses microphone reaches the app over Bluetooth hands-free audio, as 8 kHz mono. | Sound alerts and captions through the glasses microphone are marked as needing a test on the device. |
| [Apple, speech recognition for people who stutter](https://machinelearning.apple.com/research/speech-recognition) | The usual end-of-speech detector cut off 23.8% of utterances from people who stutter. A longer threshold brought that to 2.5%. | "Give me more time" lengthens every pause timer. |
| [Apple, Siri Pause Time](https://support.apple.com/guide/iphone/change-siri-accessibility-settings-iphaff1d606/ios) | The wearer chooses how long the assistant waits. | The same choice, by voice or in settings. |
| [WCAG 2.2](https://www.w3.org/TR/WCAG22/), 2.2.1 Timing Adjustable | Time limits must be adjustable. | The same setting. Removing the limit altogether is on the list below. |
| [Memoro (CHI 2024)](https://arxiv.org/abs/2403.02135) | A wearable memory aid with minimal answers cut the time spent on the device and raised confidence in recall. | "What was I doing?" answers in one or two sentences. |
| [Watch, Talk and Guide (2023)](https://arxiv.org/abs/2311.00738) | Models are still poor at judging from video whether a step was done correctly. | Task guidance waits for the wearer to say "next". |
| [Microsoft Soundscape](https://github.com/microsoft/soundscape) | Audio cues can build awareness of surroundings in a way step-by-step directions do not. | Direction tones before each callout. Audio beacons are on the list below. |

No code was copied from any of these. Detectors published under the AGPL, such as [Ultralytics YOLO](https://www.ultralytics.com/license), were left out on purpose, because that license does not fit an Apache-2.0 app. Everything on the phone uses Apple's own Vision and SoundAnalysis frameworks, so this suite adds no third-party code or models.

## Ideas not built yet

In rough order of value.

1. **A finder with a tone.** For "find the door", a beep that speeds up as the target centers, and silence when it is out of view.
2. **A framing coach.** Detect blur, cut-off text, and a covering hand before reading, and say "move it left" or "hold it further away".
3. **Two looks for anything that matters.** Read a medicine label or a banknote from two frames and speak only what agrees.
4. **Speaker labels and a personal vocabulary in captions**, plus typed replies spoken aloud.
5. **Custom sounds.** Teach the phone your own doorbell or appliance from a few examples.
6. **No time limit at all.** End a turn with a gesture or a word, never a timer.
7. **Personal command phrases and atypical-speech support.**
8. **Gestures for "next", "yes", and "no"** on the Neural Band and the glasses touchpad.
9. **Changes only.** In a place you know, say only what is different from last time.
10. **A private money mode** that answers with a tone pattern.
11. **"Where did I put it?"** for a few tagged objects.
12. **A simplified screen** with a few large actions, set up by a supporter.
13. **A verbosity setting** for descriptions and callouts, and less detail while walking.

## Checking it on the glasses

These are the checks that decide whether a row moves to Done. Start listening on the main screen first.

1. Hold a printed page and say "Hey Phoenix, read this". Then "more", "back", and "stop".
2. Hold a medicine box and say "Hey Phoenix, read the label". Compare every number with the box.
3. Hold a banknote and say "Hey Phoenix, what bill is this?". Try each denomination you have, both sides, and a coin, which it should refuse.
4. Hold up clothes in daylight and under a warm bulb and say "Hey Phoenix, what color is this?".
5. Indoors with a sighted person beside you, say "Hey Phoenix, start guide mode". Check that the notice is read, the capture light is on, people, stairs, and doors are called with the right side, and "stop guide mode" turns the light off.
6. With a friend's agreement, say "turn on face recognition", then "remember this person as" and their name. Check that it asks first, then "who is this?", then "forget" their face.
7. Outdoors with a sighted person, say "Hey Phoenix, walk me to" a nearby place. Check the turns and the distances.
8. Say "Hey Phoenix, start captions" and have someone talk to you. Check the text, check that Phoenix Fox's own voice is not captioned, then "what did they say?".
9. Turn on sound alerts and ring the doorbell, knock, and play a siren from another device, once with the glasses microphone and once with the phone's.
10. Say "Hey Phoenix, new routine called tea, the steps are fill the kettle, switch it on, pour the water". Then "start my tea routine", "next", "repeat", and "what was I doing?".
11. Turn on VoiceOver and go through first run (delete and reinstall the app to see it again), the home screen, Settings, then Accessibility, and the Captions screen. Set the text size to its largest and check that nothing on the home screen or in first run is cut off.
