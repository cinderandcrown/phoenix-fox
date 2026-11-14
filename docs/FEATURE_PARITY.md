# Feature parity with Meta AI glasses

Phoenix Fox is compared with the Meta AI app on Meta's own pages, then with what Wearables Device Access Toolkit 1.0.1 and iOS actually allow on **Meta Glasses Adventurer** (displayless `DeviceType.metaGlasses`). Display and Neural Band items are a later target. They are not faked on Adventurer.

Sources, all Meta:

- [How to use Meta AI on AI glasses](https://www.meta.com/help/ai-glasses/977597606858973/)
- [Ask Meta AI about what you see](https://www.meta.com/help/ai-glasses/718045509827730/)
- [Reminders](https://www.meta.com/help/ai-glasses/544073848068065/)
- [Timers](https://www.meta.com/help/ai-glasses/1139273053944856/)
- [Directions](https://www.meta.com/help/ai-glasses/728826956444153/)
- [Be My Eyes](https://www.meta.com/help/ai-glasses/1524316621830425/)
- [Push notifications](https://www.meta.com/help/ai-glasses/821542046337785/)
- [Release notes (QR, navigation, look-and-ask)](https://www.meta.com/help/ai-glasses/1809764829519902/)
- [Voice assistant overview](https://www.meta.com/ai-glasses/ai-glasses-voice-assistant/)
- [Voice commands](https://www.meta.com/ai-glasses/learn/voice-command/)
- [Hands-free communication](https://www.meta.com/ai-glasses/hands-free-communication/)
- DAT hardware and version table: [toolkit overview](https://wearables.developer.meta.com/docs/develop/dat) and [version dependencies](https://wearables.developer.meta.com/docs/develop/dat/version-dependencies/)

"Better with Grok Bot" means Fire Fox, Indy, Driver, or Rally do the multi-step work, and a cheap vision model answers a single look. Silence stays on the phone.

## Status

No row says Done, because nothing here has been run on a pair of glasses yet. The words mean:

- **Built**: the whole path is in the app, it compiles in CI with no warnings, and the parts that do not need hardware are covered by unit tests. The owner confirms it on Adventurer with the steps in [SETUP.md](../SETUP.md).
- **Written**: the whole path is in the app and its decisions are covered by unit tests, but CI has not built it yet. The code that calls the glasses toolkit was type-checked on Linux against stand-ins generated from the toolkit's interface. A row moves to Built when CI builds it. "Owner build" after the word means the feature is in the TestFlight build only.
- **Partial**: a real part is in the app, and the last column names what is missing.
- **Blocked**: Meta or iOS does not allow it. The app says so out loud.
- **Not started**: asked for and not built yet.

A row moves to Done when the owner has seen it work on the glasses.

Display glasses and the Neural Band do not get a second code path. `CompanionSurface.present` speaks every reply and adds a lens card only when the glasses report a display. `GestureMap` turns a tap, a swipe, or the capture button into talk, look, keep, or note, and those enter the same turn as a spoken command. On Adventurer the controls are an owner-build feature, live only while Jarvis is busy with the wearer or the camera is on, and they share one session with the camera. See [GLASSES_SDK.md](GLASSES_SDK.md).

| Feature | Status | What remains |
| --- | --- | --- |
| DAT pairing and device session | Built | Owner: Developer Mode in Meta AI, then Register App. If the glasses SDK cannot start, the app still opens and shows the reason on the Glasses screen. Adventurer is `DeviceType.metaGlasses`. |
| Jarvis wake word | Built | The phone hears it over Bluetooth. A comma after the wake word no longer hides "ask Indy". Owner confirms it is heard with the glasses on. |
| "Hey Meta" opens Phoenix Fox | Partial | The wake word stays Meta's. A launch from the glasses starts the Jarvis session. Whether Meta AI hands the launch to this app is unconfirmed. |
| On-device Whisper | Built | The `base` model downloads on first speech. The first request and each follow-up are re-heard by Whisper. If the model is not there, the Apple transcript is used. |
| One camera still, light on | Built | "Take a picture" and look-and-ask. The stream stops after the shot. Owner confirms the light matches the stream. |
| Ask a bot ("ask Indy about X") | Built | Routing is covered by `V1PathTests`, and the relay calls by `RelayClientTests`. Needs the relay token in Settings. |
| Spoken replies on the glasses | Built | Bluetooth speaker when the glasses are the audio route. A reply from a bot other than the default is spoken with its name. Per-bot voices are stored and not yet used. |
| Push alerts | Partial | The inbox long-poll speaks alerts while the app is open. The push token is sent to the relay once a relay is saved. Closed-app delivery needs the relay pull request deployed and has not been seen on a phone. |
| Look and ask, text in view, read aloud | Built | One compressed photo, then the camera turns off. Fast mode uses Grok when a key is saved. Otherwise the same photo goes to the relay. |
| Live conversation after Jarvis | Partial | Follow-ups stay open until silence. Barging in on a reply is not used, because the glasses microphones hear the speakers. Say Jarvis, then the next request. |
| Translation and meeting notes | Partial | The next utterances can be translated on the phone. "Meeting notes" sends that transcript to Fire Fox when the relay is set. No lens captions on Adventurer. No always-on interpreter. |
| Messages, SMS, email | Partial | Contacts lookup, then the public URL. You still tap send. No silent send. |
| Record a clip | Partial | The stream is saved to Photos while the light is on. In the owner build it is 720 by 1280 at 30 frames a second with the glasses' own sound at 48 kHz, the most the toolkit gives. It is not Meta's 3K file. |
| QR | Built | Vision on one photo. An `https` link opens. |
| Reminders, timers, time, date, battery | Built | On the phone, or `Device.batteryLevel` when the link is up. Time and date use no model. |
| Remember / recall | Built | AES-GCM notes, key in the Keychain. Search is on-device word vectors, not a photo embedding. |
| Calls | Partial | `tel:` opens Phone after a Contacts lookup. |
| Music play, pause, next, previous | Partial | System player only. The app says so when that is all it can reach. |
| Share a photo into Meta's apps | Partial | The still goes to Photos. There is no hand-off into Messenger or Instagram. |
| Walking directions | Partial | First spoken step, then Apple Maps. No continuous guidance. |
| Concierge booking | Partial | The request goes to the named bot through the relay. The app does not book anything itself. |
| Take over, all bots at once | Partial | Fire Fox, Indy, Driver, and Rally are asked together, and each reply is spoken as it arrives. Not yet run against the live relay. |
| Smart Capture | Partial | Session, change detection, keep/skip, Photos album, encrypted index. Auto-route stays off until you turn it on. |
| Watch this | Partial | Stream at 7 fps with the light on, at 720 by 1280 in the owner build. Only a changed frame is sent. "Stop watching" ends it. |
| Morning brief and place reminders | Partial | One brief when the relay is set. A 150 meter region speaks on entry and needs Always location. |
| In-lens cards | Blocked on Adventurer | Replies and urgent alerts already go through `CompanionSurface.present`, which draws a card when the glasses report a display. Display glasses are the remaining hardware test. |
| Touchpad, capture button, nod and shake | Written, owner build | While Jarvis is busy with the wearer: a double tap talks, a swipe back stops Jarvis talking, the capture button looks (one press), keeps a picture (two), or takes a note (hold), a shake says no, and two nods say yes where a spoken yes is not required. Not yet run on glasses. The touchpad cannot start a conversation from nothing, because an always-open session would take the glasses' single tap and long press away all day. |
| Whole-sensor photos | Written, owner build | "Take a picture" saves 4032 by 3024. Reading uses a large photo. Falls back to a stream frame. Not yet run on glasses. |
| Speech on the glasses | Written, owner build | The glasses' recognizer listens for the wake word when the phone's microphone is not listening. Needs the glasses' microphone allowed in Meta AI. Not yet run on glasses. |
| Owner build | Written | One build setting, on for TestFlight, switches every feature on once and allows the toolkit's beta parts. Covered by `OwnerBuildTests` and `OwnerProfileSettingsTests`, and checked in the signed app before upload. |
| Workshop: ten features from the [innovation backlog](INNOVATION_BACKLOG.md) | Written, owner build | Walk-through, Tally, Ingredient watch, Dose guard, Council, Relay race, Standing orders, Place notes, Close the day, and Skills, each with its own switch under Settings, Owner build, Workshop. None has run on glasses or against the live relay. The two about health are aids, not medical devices. What each one does not do yet is in the backlog's [status table](INNOVATION_BACKLOG.md#status), and the skill file format is in [SKILLS.md](SKILLS.md). |
| Plans and subscriptions | Written, switched off | Free, Own AI, Included AI, and Bot Team, with StoreKit 2. No build sells anything today, and the owner build never can: everything is unlocked. The accessibility suite and the model on the phone are never locked. The rules are unit-tested; the StoreKit code and the Plan screen have not been compiled by Xcode or run against the App Store. [BUSINESS_MODEL.md](BUSINESS_MODEL.md) |
| Neural Band | Blocked on Adventurer | Listened for on display glasses and handled like the touchpad. Nothing waits on a band. |
| WhatsApp, Messenger, Instagram calls | Blocked | Spoken. No public API, and DAT does not hand the camera to another calling app. |
| Read other apps' notifications | Blocked | Spoken. iOS keeps those private. |
| Set the system volume | Blocked | The level is spoken. The rocker on the glasses stays in charge. |
| Be My Eyes volunteer video | Blocked | A description from the phone is offered instead. See [Accessibility, compared with Be My Eyes](#accessibility-compared-with-be-my-eyes). |
| Workout stats | Partial | Not wired. HealthKit is the later path. It is not claimed. |
| Mind meld | Built | Off until "mind meld on". Stores words on the phone. "What should I do" proposes one bot ask. "Do that" or "have Indy handle that" sends it. No camera bytes. |
| Choose Grok, ChatGPT, Gemini, Claude, or your own assistant | Partial | The backends are in the app and Settings switches between them. The default is the relay. One setting that swaps the bot team for another provider with the same wake word, and a paid tier for the bot team, are not built. |
| Guide mode for blind and low-vision users | Partial | Written: hazard callouts with direction tones, scene description, sign and document reading, finding objects, turn-by-turn walking directions, the emergency contact, and the safety notice. It has not been built by Xcode in CI yet or run on the glasses. Curbs and drop-offs are not detected reliably. Each part has its own row in [ACCESSIBILITY.md](ACCESSIBILITY.md). |
| Accessibility suite and [ACCESSIBILITY.md](ACCESSIBILITY.md) | Partial | Written for blind and low-vision, Deaf and hard-of-hearing, speech and motor, and memory and task support, with a status row for each feature. It has not been built by Xcode in CI yet or run on the glasses. The Accessibility and Captions screens are made for VoiceOver. A full VoiceOver pass over the rest of the app has not been done. |

## Mind meld

This is not a Meta feature. It is the on-phone half of the bot team.

Say "mind meld on". After that, finished turns are written to `phoenix-mindmeld.json` in the app's documents: what you said, what came back, and, if you asked for a look, the words of that question. The file is not a camera roll. "Remember this" is still the encrypted note path, and it is the only one that keeps a JPEG, with the capture light on.

"What should I do" does not call a model. It names a bot and a next ask from the log and the clock, then waits. "Do that", "have Indy handle that", or "send this to Driver" is the hands-free send through the relay. "Mind meld off" stops the log and leaves the encrypted notes alone.

| Meta feature | On Adventurer with DAT 1.0.1 and iOS | Phoenix Fox |
| --- | --- | --- |
| Wake with "Hey Meta" or a touchpad hold | **Partial.** The hardware wake word stays Meta's. DAT does not let another app register "Hey Meta" or replace it. The touchpad can report a tap only while a session is open, and an open session takes the glasses' single tap and long press for itself, so Phoenix Fox opens one only while Jarvis is already busy with the wearer (owner build). | Say **Jarvis**. The phone hears it over Bluetooth. Meta's wake word is unchanged. |
| Look and ask / describe what I see | **Yes.** One still from `Camera` / the preview stream, then the camera turns off. | One compressed photo. A short question uses the cheap Grok model. A task goes to the relay. |
| Live AI, continuous conversation | **Partial.** No always-on glasses assistant. After Jarvis, follow-ups work until silence. During "watch this" and translation, the conversation stays open and "Jarvis" plus the next request interrupts speech. Any-speech barge-in is not used, because the glasses mic hears the reply. | Same conversation window. The camera stays off unless you ask to look or watch. |
| Live translation of a conversation | **Partial.** No Meta interpreter session and no lens captions on Adventurer. | "Start translating" or "translate to Spanish" captions the phone and speaks the translation. Meeting notes summarize that transcript. |
| WhatsApp / Messenger / Instagram messages | **Partial.** No silent send. A public URL opens WhatsApp, Messenger, Mail, or Messages with the words filled in, after a Contacts lookup. The wearer taps send. | "Text" or "email" plus a name. |
| Record 3K video the way Meta's camera button does | **Partial.** DAT gives a preview stream, not the glasses' own 3K file. | "Record a clip" saves that preview to Photos while the hardware light stays on, and says it is not Meta's 3K file. |
| Translate text in view | **Yes.** One photo plus a vision model. | Same, cheap model, camera off after the shot. |
| Read text aloud | **Yes.** Same one-photo path. | Same. |
| Scan a QR code | **Yes.** Vision framework on one photo. Meta also pushes a phone notification from their app. We can open an `https` link. | Reads the code and opens an https link. Does not claim Meta's notification pipeline. |
| Reminders, including "remember this tracking number" | **Yes.** Apple Reminders, plus encrypted on-phone notes. A photo can be stored with the note. Search uses on-device word vectors. | "Remind me…" writes Apple Reminders. "Remember…" is encrypted on the phone. |
| Timers | **Yes.** A local notification. Up to 24 hours, matching Meta's limit in their help page. | "Set a timer for 5 minutes." |
| Calls on the phone | **Partial.** `tel:` opens the Phone app. Contacts can be searched after permission. | "Call" plus a name or number. |
| WhatsApp, Messenger, Instagram calls and POV video calls | **Blocked.** Those apps do not offer a public API for a glasses camera call, and DAT does not hand the camera to another VoIP app. | The app says so. It does not place the call. |
| SMS | **Partial.** `sms:` opens Messages after a Contacts lookup. The wearer finishes the send. | "Text" plus a name or number. |
| Announce and read incoming messages from other apps | **Blocked.** iOS does not let an app read WhatsApp, Messenger, or Messages notifications. | Says that, and only speaks timers and reminders Phoenix Fox created. |
| Music play, pause, next, previous | **Partial.** `MPMusicPlayerController` controls the system player, not every third-party app. | Those four commands, and it says when it is only the system player. |
| Set the volume from an app | **Blocked.** Setting the system volume from an app is not a public iOS API. Reading it is allowed. | Speaks the current level and leaves the glasses rocker in charge. |
| Hear music and calls on the glasses speakers | **Yes.** Bluetooth HFP / A2DP, which is the path Meta documents for mic and speaker. | Replies use that route when the glasses are the connected audio device. |
| Take a photo and save it | **Yes.** One still, then Photos library. The hardware light is on for the shot. | "Take a picture." |
| Share a photo to a contact inside Meta's apps | **Partial.** Saving to Photos is real. Hand-off into Messenger or Instagram is not. | Saves the still. Does not claim the Meta share sheet. |
| Walking navigation with spoken steps | **Partial.** Apple Maps can search, speak the first walking step, and open the map. Meta's continuous guidance and companion map are theirs. | "Navigate to" speaks the first step and opens Apple Maps. "Walk me to" plans a walking route and speaks every turn, with re-routing. It is written and not yet run on the glasses. See [ACCESSIBILITY.md](ACCESSIBILITY.md). |
| In-lens captions, maps, message previews | **Blocked on Adventurer.** `supportsDisplay` is false. HUD code runs only when a display is reported. | Spoken answer only. |
| Neural Band pinch and swipe | **Blocked on Adventurer.** The band is not part of this product. DAT exposes semantic taps, not raw EMG, and only when that hardware is present. | No gesture is required. |
| Be My Eyes volunteer video | **Blocked.** Meta's help page requires the Meta AI app connection. A third-party app cannot join that volunteer network. | Offers a one-photo description instead, and says the volunteer call stays in Meta AI. |
| "What time is it" / date | **Yes.** On the phone. No model call. | Spoken locally. |
| Glasses battery | **Yes.** `Device.batteryLevel` when the link is up. | Spoken locally. |
| Workout stats from a connected fitness app | **Blocked** for Meta's connector. HealthKit could be added later. It is not wired, and it is not claimed. | Not implemented. |
| Concierge booking | **Partial.** No Meta concierge API. A booking request can go to the relay as agent work. | Named assistants handle it if the relay is configured. The app does not book by itself. |

## What was built

Local, no model cost: time, date, battery, timers, Apple Reminders, a remember/recall list, system music transport, volume read-out, one saved photo, QR read, a first walking step plus Apple Maps, phone calls, and SMS hand-off.

One cheap vision call, camera off afterward: look-and-ask, including text in view, when fast mode and a Grok key are on. Otherwise the same photo goes to the relay.

Agent work: Fire Fox, Indy, Driver, and Rally through the relay, after the local commands above have had their chance.

## What stays blocked, and why

Meta keeps "Hey Meta", the volunteer Be My Eyes session, WhatsApp / Messenger / Instagram calling and POV video, notification readout, silent social messaging, 3K glasses video files, in-lens UI, and the Neural Band on hardware that Adventurer does not have. iOS keeps other apps' notifications private and does not allow an app to set the system volume. Phoenix Fox says that out loud instead of inventing a success.

## Beyond Meta

These are the extra companion behaviors, still only where a public API exists. The camera light is Meta's hardware. Phoenix Fox does not turn it off and does not record unless you ask.

| Item | Status | Where |
| --- | --- | --- |
| 1. Jarvis always-listening, App Intent, Action Button, Live Activity | **Partial.** Listening stays up across tabs and in the background audio session, with the system mic indicator. The shortcut is "Wake Jarvis in Phoenix Fox", which is what you assign to the Action Button. Apple will not register a bare "Hey Siri, Jarvis". A Live Activity is requested. There is no widget extension, so the island has no custom layout. | `OpenVision/Services/Voice/VoiceCommandService.swift`, `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift`, `OpenVision/Resources/Info.plist` |
| 2. WhatsApp, Messenger, SMS, email handoff with Contacts | **Partial.** Opens the app with the text filled in and looks up the contact. The wearer still taps send. No silent send, and no in-app chat list. | `OpenVision/Services/Brain/Companion.swift` (`MessageHandoff`), `OpenVision/Services/Brain/PhoenixFoxFeatures.swift` |
| 3. Bot inbox, relay push, APNs, read aloud, voice reply | **Partial.** The worker in `relay/` implements `/ask`, `/pending`, `/reply/{id}`, `/push`, `/inbox`, and `/device`. The app long-polls the inbox and registers its APNs token. Pushes send only after the APNs secrets are set, and this repo does not deploy the worker. | `relay/`, `docs/RELAY_API.md`, `OpenVision/Services/Brain/OwnAssistantService.swift` |
| 4. Watch this, adaptive rate, change detection, live conversation, barge-in | **Partial.** The DAT stream stays at 7 fps with the light on. Inspection moves between about 0.4s and 2.5s when the scene changes, and only a changed frame goes to Grok. The conversation stays open. Interrupting speech still requires "Jarvis" plus the next request, so the reply echoing in the mic is not treated as a new command. | `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Services/LiveVision/FrameChange.swift`, `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` |
| 5. Grok, take over, parallel dispatch, spoken progress, task history | **Partial.** Fire Fox, Indy, Driver, and Rally are requested at the same time, and each reply is spoken as it arrives. The list is in Settings. This needs the relay, which is not running here. | `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Services/Brain/OwnAssistantService.swift`, `OpenVision/Views/Settings/SettingsView.swift` |
| 6. Encrypted memory and photo memories, semantic search | **Partial.** Notes and an optional photo are sealed with AES-GCM. The key is in the Keychain. Search ranks on-device word vectors from `NLEmbedding`, which is a bag of words, not a photo embedding model. | `OpenVision/Services/Brain/Companion.swift` (`SecureNotes`), `OpenVision/Services/Brain/PhoenixFoxFeatures.swift` |
| 7. Live translation, captions, meeting notes | **Partial.** Spoken translation and on-phone captions for the utterances you choose. "Meeting notes" sends that transcript to Fire Fox when the relay is set. No lens captions on Adventurer, and no always-on interpreter. | `OpenVision/Services/Brain/Companion.swift` (`TranscriptLog`) |
| 8. Morning brief and geofenced reminders | **Partial.** One brief each morning when the relay is configured. "When I arrive at … remind me to …" arms a 150 meter region and speaks on entry. Background arrival needs Always location, and the location arrow stays on. | `OpenVision/Services/Brain/Companion.swift` (`PlaceReminders`), `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` |
| 9. Voice photo and video with the hardware LED | **Partial.** "Take a picture" saves a still. "Record a clip" saves the preview stream to Photos and only runs while that stream, and its light, are on. It is not Meta's 3K file, and nothing records unless you ask. | `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Services/Recording/SessionRecorder.swift`, `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` |

| Ask Jarvis | What happens | Cost |
| --- | --- | --- |
| Wake word while the app is in front, or while the audio session is still up | The existing on-device voice-activity check runs first. Whisper runs after speech, not on silence. The orange mic indicator stays. | No model until you speak. |
| Hey Siri, then the Phoenix Fox shortcut | An App Intent named Jarvis opens the app. Apple requires the app name in the phrase, so it is "Wake Jarvis in Phoenix Fox", and you assign that shortcut to the Action Button. | None. |
| Dynamic Island | A Live Activity is requested with the listening or camera line. The in-app status line is the one that always shows. | None. |
| Text someone on WhatsApp, Messenger, SMS, or email | The dictated words are filled into that app's public URL or the share sheet. You still tap send. Contacts supplies the number or address after you allow it. | None. |
| A relay alert | The phone long-polls the inbox and can register for push. Urgent lines interrupt speech. Ordinary lines wait. Low ones sit until the morning brief. Say "reply …" to answer the last one. | A few bytes, plus one relay ask for the reply. |
| Watch this | The official camera stream starts, so the glasses light is on, and a banner says so. Frames are compared on the phone. Only a changed frame goes to the cheap vision model. Say stop watching and the stream stops. | One cheap call per real scene change. |
| Grok, take over | The same request is sent to Fire Fox, Indy, Driver, and Rally together. You hear each result as it arrives. The list is saved on the phone. | Relay only. |
| Remember this, including a photo note | Stored on the phone, encrypted with a key that stays in the Keychain. "Where did I park" searches that list on device. | No cloud. |
| Translate, then summarize the meeting | The next utterances are translated and shown on the phone. A summary is a short relay brief. There is no lens caption on Adventurer. | One short call per utterance you chose. |
| Morning brief | Once each morning, if the relay is set, the assistants are asked for a short brief. | One relay round. |
| Record a clip | Uses the existing recorder, which only runs while the camera stream is up. The light stays on. The file goes to Photos. | No model. |

## Accessibility, compared with Be My Eyes

Meta's accessibility feature on these glasses is "Call a Volunteer", made with Be My Eyes: a sighted volunteer sees the camera view and talks the wearer through a task. Meta AI can also give more detailed descriptions. Both are part of the Meta AI app, and a third-party app cannot join them.

A person is better than software at many of these tasks, and Phoenix Fox does not claim otherwise. What it adds is help that needs no other person, no signal for most of it, and no wait. The full list, the safety limits, and the sources are in [ACCESSIBILITY.md](ACCESSIBILITY.md).

| | Be My Eyes on Meta glasses | Phoenix Fox |
| --- | --- | --- |
| Who is looking | A sighted volunteer, live. | The phone. A model only for scene descriptions and finding things. |
| Needs a connection | Yes. | No, for reading, money, labels, colors, faces, callouts, sound alerts, and tasks. Yes, for walking routes and model descriptions. |
| Reading text, labels, money | The volunteer reads it. | Read on the phone, word for word. Medicine labels in a fixed order. Unclear numbers are left out. |
| Moving around | The volunteer describes what they see. | Guide mode calls out people, vehicles, stairs, doors, and signs with direction tones. Walking directions speak each turn. Neither replaces a cane or a guide dog. |
| Recognizing people | Not part of it. | Only people saved with their spoken agreement, kept on the phone. |
| Hearing | Not part of it. | Live captions, sound alerts, your name called, saved transcripts. |
| Tasks and memory | Not part of it. | Step-by-step routines, reminders for a person or a place, "what was I doing?". |
| Privacy | A stranger sees the camera view for the length of the call. | Pictures stay on the phone unless a model description is asked for. |
| When it is wrong | A person can say "I'm not sure, turn it over". | It says when it cannot tell, and it will still make mistakes a person would not. |
| Status | Shipping. | Written, not yet run on the glasses. |

## Smart Capture

Meta’s glasses take a still or a video when you press the capture button or say “Hey Meta, take a photo” or “take a video.” That file is stored by Meta’s camera. Meta does not hand another app a silent always-on classifier, and the hardware light is on whenever the camera is open.

Phoenix Fox Smart Capture is a session you start with “Jarvis, smart capture on” or the Settings toggle. The DAT preview stream runs, so the glasses light stays on, and the app says so. It stops when you say “smart capture off,” when the timer ends (30 minutes unless you change it), or when the keep limit is reached. On-device change detection and a contrast score pick candidate frames. Only those frames go to Grok, and only up to the session’s call cap. Grok returns keep or skip, tags, a short caption, and a suggested action: receipt, business card, whiteboard, or highlight. Kept frames go to a Photos album named Phoenix Fox and to an encrypted index on the phone. “Show me the receipts from today” speaks the matching captions. Auto-route is off until you turn it on. Then a receipt can be sent to Fire Fox, a card can be saved to Contacts, a whiteboard can be stored in notes, and highlights are spoken in the morning brief.

This is not Meta’s camera roll, and it is not a hidden recording. If the stream cannot start, nothing is captured.

