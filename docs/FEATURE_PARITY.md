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

**Done** means the Adventurer behavior is in the app and has no open product gap. **Partial** means it runs, and the Remaining column is still open. **Blocked** means Meta or iOS does not allow it. The app says so out loud instead of pretending. Nothing below has been worn on Adventurer yet. The owner confirms the Partial rows that touch the glasses, the mic, or push. The simulator CI only proves the code compiles.

Display and Neural Band do not get a second command path. `CompanionSurface` speaks every reply and adds a lens card only when `supportsDisplay` is true. `GestureMap` turns DAT input into talk, look, and note. `VoiceAgentViewModel` is the only listener. Adventurer never opens that input session, because it would compete with the camera.

| Feature | Status | Remaining |
| --- | --- | --- |
| Jarvis wake on the phone mic | Partial | Owner confirms Bluetooth HFP hears "Jarvis" with the glasses on. Whisper re-hears the command and the follow-up. Apple speech is the fallback if the model has not downloaded. |
| Hey Meta launches Phoenix Fox | Partial | The hardware word stays Meta's. A `LaunchApp` invocation now starts the Jarvis session. Owner confirms the Meta AI app actually hands the launch to this bundle id. |
| Temple tap / Neural Band | Blocked on Adventurer | The input session stays down so the camera can open. On display glasses the same notifications already call talk, look, and note. |
| Look and ask, text in view, read aloud | Partial | One preview frame, then the stream stops and the hardware light goes off. Owner confirms a frame arrives on Adventurer and the light matches the stream. |
| Ask a named bot ("ask Indy about X") | Partial | Routed in code and covered by `V1PathTests`. Needs the relay URL and token on the phone, and the worker deployed. |
| Spoken replies | Partial | The selected voice speaks the line. A non-default bot is prefixed with its name. Per-bot voice identifiers are stored and not yet applied to TTS. |
| Push alerts | Partial | Token is kept and registered when the relay is saved. Urgent pushes wake the app and are spoken from the inbox. Needs Apple push secrets on the worker, `APNS_USE_SANDBOX=false` for TestFlight, and the owner accepting notifications. Long-poll works without push. |
| Live conversation after Jarvis | Partial | Follow-ups stay open until silence. Barge-in still requires "Jarvis" plus the next request, so the glasses mic does not treat the reply as a command. |
| Live translation and meeting notes | Partial | Phone captions and speech. A summary needs the relay. No lens captions on Adventurer. |
| Messages, SMS, email handoff | Partial | The app fills WhatsApp, Messenger, Mail, or Messages. The wearer taps send. |
| Record a clip | Partial | Saves the preview stream to Photos while the light is on. It is not Meta's 3K file. |
| QR, reminders, timers, time, date | Partial | On-phone. Time and date do not call a model. Owner confirms speech and the Reminders permission. |
| Phone calls | Partial | `tel:` opens Phone after a Contacts lookup. |
| Music play, pause, next, previous | Partial | System player only. The app says when that is the limit. |
| Volume | Blocked | Reading the level is allowed. Setting it is not a public iOS API. The glasses rocker stays in charge. |
| Hear replies on the glasses | Partial | Bluetooth HFP / A2DP when the glasses are the audio route. Owner confirms the speaker, not the phone earpiece. |
| Take a photo | Partial | "Take a picture" saves a still. The light is on for the shot. |
| Share into Meta's apps | Partial | The still goes to Photos. There is no Messenger or Instagram handoff. |
| Walking directions | Partial | First step spoken, Apple Maps opened. Not Meta's continuous guidance. |
| In-lens captions, maps, message previews | Blocked on Adventurer | `CompanionSurface` already renders when a display is reported. No Adventurer work left. |
| Be My Eyes volunteer video | Blocked | One-photo description instead. The volunteer call stays in Meta AI. |
| Other apps' notification readout | Blocked | iOS does not allow it. Timers and reminders Phoenix Fox created are spoken. |
| WhatsApp, Messenger, Instagram calls and POV video | Blocked | No public API. The app says so. |
| Workout stats | Blocked | Not wired. HealthKit is not claimed. |
| Concierge booking | Partial | Goes to the named bot through the relay. The app does not book by itself. |
| Smart Capture | Partial | Session, on-device gating, Grok keep/skip, Photos album, encrypted index. Auto-route is off until the owner turns it on. Owner confirms the light stays on for the session and that Grok calls stop at the cap. |
| Watch this / frame-change gating | Partial | 8 fps stream, changed frames only. Covered by `FrameChangeTests` for the diff. Owner confirms the light and the stop phrase. |
| Take over / parallel bots | Partial | Fire Fox, Indy, Driver, and Rally are asked together. Needs a running relay. |
| Encrypted memory | Partial | AES-GCM, key in the Keychain. Search is on-device word vectors, not a photo embedding. |
| Morning brief and geofenced reminders | Partial | One brief when the relay is set. Arrival needs Always location, and the location arrow stays on. |
| Provider choice (Grok, ChatGPT, Gemini, Claude, on-device) | Partial | Settings already switch backends. Grok Bot multi-bot control is the default. A paid-only gate for extra bots is not enforced (`isPro` is true on the Phoenix Fox turn). |

The behavior tables under this section are the spec those rows are judged against.

| Meta feature | On Adventurer with DAT 1.0.1 and iOS | Phoenix Fox |
| --- | --- | --- |
| Wake with "Hey Meta" or a touchpad hold | **Partial.** The hardware wake word stays Meta's. DAT does not let another app register "Hey Meta" or replace it. The touchpad can report a tap only while an input session is up. Adventurer does not keep that session open, because it would block the camera. | Say **Jarvis**. The phone hears it over Bluetooth. Meta's wake word is unchanged. |
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
| Walking navigation with spoken steps | **Partial.** Apple Maps can search, speak the first walking step, and open the map. Meta's continuous guidance and companion map are theirs. | First step spoken, Apple Maps opened, limitation spoken. |
| In-lens captions, maps, message previews | **Blocked on Adventurer.** `supportsDisplay` is false. `CompanionSurface` speaks, and adds a lens card only when a display is reported. | Spoken answer only. |
| Neural Band pinch and swipe | **Blocked on Adventurer.** The band is not part of this product. DAT exposes semantic taps, not raw EMG. `GestureMap` already turns those taps into talk, look, and note when an input session exists. Adventurer does not open that session. | No gesture is required. |
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
| 1. Jarvis always-listening, App Intent, Action Button, Live Activity | **Partial.** Listening stays up across tabs and in the background audio session, with the system mic indicator. The shortcut is "Wake Jarvis in Phoenix Fox", which is what you assign to the Action Button. Apple will not register a bare "Hey Siri, Jarvis". A Live Activity is requested. There is no widget extension, so the island has no custom layout. Whisper hears the wake command and each follow-up. Hey Meta launch and display-glasses gestures enter the same session. | `OpenVision/Services/Voice/VoiceCommandService.swift`, `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift`, `OpenVision/Resources/Info.plist` |
| 2. WhatsApp, Messenger, SMS, email handoff with Contacts | **Partial.** Opens the app with the text filled in and looks up the contact. The wearer still taps send. No silent send, and no in-app chat list. | `OpenVision/Services/Brain/Companion.swift` (`MessageHandoff`), `OpenVision/Services/Brain/PhoenixFoxFeatures.swift` |
| 3. Bot inbox, relay push, APNs, read aloud, voice reply | **Partial.** The worker in `relay/` implements `/ask`, `/pending`, `/reply/{id}`, `/push`, `/inbox`, and `/device`. The app long-polls the inbox, stores the APNs token, and registers it when the relay is saved. Urgent pushes also wake the app. Pushes send only after the APNs secrets are set. TestFlight uses production APNs. This repo does not deploy the worker. | `relay/`, `docs/RELAY_API.md`, `OpenVision/Services/Brain/OwnAssistantService.swift` |
| 4. Watch this, adaptive rate, change detection, live conversation, barge-in | **Partial.** The DAT stream stays at 8 fps with the light on. Inspection moves between about 0.4s and 2.5s when the scene changes, and only a changed frame goes to Grok. The conversation stays open. Interrupting speech still requires "Jarvis" plus the next request, so the reply echoing in the mic is not treated as a new command. | `OpenVision/Services/Brain/Companion.swift`, `OpenVision/Services/LiveVision/FrameChange.swift`, `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` |
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

## Smart Capture

Meta’s glasses take a still or a video when you press the capture button or say “Hey Meta, take a photo” or “take a video.” That file is stored by Meta’s camera. Meta does not hand another app a silent always-on classifier, and the hardware light is on whenever the camera is open.

Phoenix Fox Smart Capture is a session you start with “Jarvis, smart capture on” or the Settings toggle. The DAT preview stream runs, so the glasses light stays on, and the app says so. It stops when you say “smart capture off,” when the timer ends (30 minutes unless you change it), or when the keep limit is reached. On-device change detection and a contrast score pick candidate frames. Only those frames go to Grok, and only up to the session’s call cap. Grok returns keep or skip, tags, a short caption, and a suggested action: receipt, business card, whiteboard, or highlight. Kept frames go to a Photos album named Phoenix Fox and to an encrypted index on the phone. “Show me the receipts from today” speaks the matching captions. Auto-route is off until you turn it on. Then a receipt can be sent to Fire Fox, a card can be saved to Contacts, a whiteboard can be stored in notes, and highlights are spoken in the morning brief.

This is not Meta’s camera roll, and it is not a hidden recording. If the stream cannot start, nothing is captured.

