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

| Meta feature | On Adventurer with DAT 1.0.1 and iOS | Phoenix Fox |
| --- | --- | --- |
| Wake with "Hey Meta" or a touchpad hold | **Partial.** The hardware wake word stays Meta's. DAT does not let another app register "Hey Meta" or replace it. The touchpad can report a tap only while an input session is up. Adventurer does not keep that session open, because it would block the camera. | Say **Jarvis**. The phone hears it over Bluetooth. Meta's wake word is unchanged. |
| Look and ask / describe what I see | **Yes.** One still from `Camera` / the preview stream, then the camera turns off. | One compressed photo. A short question uses the cheap Grok model. A task goes to the relay. |
| Live AI, continuous conversation | **Partial.** No always-on glasses assistant. After Jarvis, follow-ups work until silence. The camera is not left on. | Same conversation window, no continuous video. |
| Live translation of a conversation | **Partial.** No Meta interpreter session and no lens captions on Adventurer. | Translates the next utterance, or a sign in one photo. Says clearly that a two-way interpreter is Meta's feature. |
| Translate text in view | **Yes.** One photo plus a vision model. | Same, cheap model, camera off after the shot. |
| Read text aloud | **Yes.** Same one-photo path. | Same. |
| Scan a QR code | **Yes.** Vision framework on one photo. Meta also pushes a phone notification from their app. We can open an `https` link. | Reads the code and opens an https link. Does not claim Meta's notification pipeline. |
| Reminders, including "remember this tracking number" | **Yes.** Apple Reminders, plus a local memory list on the phone. Location on the reminder is optional and off unless the owner turns location on. | "Remind me…" writes Apple Reminders. "Remember…" is stored on the phone and can be asked back. The relay can do the longer version. |
| Timers | **Yes.** A local notification. Up to 24 hours, matching Meta's limit in their help page. | "Set a timer for 5 minutes." |
| Calls on the phone | **Partial.** `tel:` opens the Phone app. Contacts can be searched after permission. | "Call" plus a name or number. |
| WhatsApp, Messenger, Instagram calls and POV video calls | **Blocked.** Those apps do not offer a public API for a glasses camera call, and DAT does not hand the camera to another VoIP app. | The app says so. It does not place the call. |
| SMS | **Partial.** `sms:` opens Messages. The wearer finishes the send. | "Text" plus a number opens Messages. |
| WhatsApp / Messenger / Instagram messages | **Blocked** as a send from the glasses. URL schemes can open a chat only with a phone number, and still need the wearer to tap send. | Refuses the silent send and says why. |
| Announce and read incoming messages from other apps | **Blocked.** iOS does not let an app read WhatsApp, Messenger, or Messages notifications. | Says that, and only speaks timers and reminders Phoenix Fox created. |
| Music play, pause, next, previous | **Partial.** `MPMusicPlayerController` controls the system player, not every third-party app. | Those four commands, and it says when it is only the system player. |
| Set the volume from an app | **Blocked.** Setting the system volume from an app is not a public iOS API. Reading it is allowed. | Speaks the current level and leaves the glasses rocker in charge. |
| Hear music and calls on the glasses speakers | **Yes.** Bluetooth HFP / A2DP, which is the path Meta documents for mic and speaker. | Replies use that route when the glasses are the connected audio device. |
| Take a photo and save it | **Yes.** One still, then Photos library. | "Take a picture." |
| Record 3K video the way Meta's camera button does | **Blocked.** DAT gives a preview stream, not the glasses' own video file. | Says so. Does not save a fake video. |
| Share a photo to a contact inside Meta's apps | **Partial.** Saving to Photos is real. Hand-off into Messenger or Instagram is not. | Saves the still. Does not claim the Meta share sheet. |
| Walking navigation with spoken steps | **Partial.** Apple Maps can search, speak the first walking step, and open the map. Meta's continuous guidance and companion map are theirs. | First step spoken, Apple Maps opened, limitation spoken. |
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

| Ask Jarvis | What happens | Cost |
| --- | --- | --- |
| Wake word while the app is in front, or while the audio session is still up | The existing on-device voice-activity check runs first. Whisper runs after speech, not on silence. The orange mic dot stays. iOS will not keep a hidden mic alive with no audio session. | No model until you speak. |
| Hey Siri, then the Phoenix Fox shortcut | An App Intent named Jarvis opens the app. Apple requires the app name in the phrase, so it is "Wake Jarvis in Phoenix Fox", and you can put that shortcut on the Action Button. A bare "Hey Siri, Jarvis" with no app name is not something Apple lets a third party register. | None. |
| Dynamic Island | A Live Activity is requested with the listening or camera line. The in-app status line is the one that always shows. A custom island layout is not a second hidden recorder. | None. |
| Text someone on WhatsApp, Messenger, SMS, or email | The dictated words are filled into that app's public URL or the share sheet. You still tap send. Contacts supplies the number or address after you allow it. | None. |
| A relay alert | The phone can register for push. Urgent lines interrupt speech. Ordinary lines wait. Low ones sit until the morning brief. If Apple push is not configured, nothing is invented. | A few bytes. |
| Watch this | The official camera stream starts, so the glasses light is on, and a banner says so. Frames are compared on the phone. Only a changed frame goes to the cheap vision model, and only a handful. Say stop watching and the stream stops. | One cheap call per real scene change. |
| Grok, take over | The same request is sent to Fire Fox, Indy, Driver, and Rally. You hear each result. The list is saved on the phone. | Relay only. |
| Remember this, including a photo note | Stored on the phone, encrypted with a key that stays in the Keychain. "Where did I park" searches that list on device. | No cloud. |
| Translate, then summarize the meeting | The next utterances are translated by the cheap model and appended to a transcript. A summary is a short relay brief. There is no always-on interpreter and no lens captions on Adventurer. | One short call per utterance you chose. |
| Morning brief | Once each morning, if the relay is set, the assistants are asked for a short brief. | One relay round. |
| Record a clip | Uses the existing recorder, which only runs while the camera stream is up. The light stays on. The file goes to Photos. | No model. |

