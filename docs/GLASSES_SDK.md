# Glasses and the official toolkit

Phoenix Fox talks to the glasses only through Meta's Wearables Device Access Toolkit for iOS. The wearer says Jarvis. That is the wake word, not the product name.

Hardware honesty here supports the product north star in [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md): presence with the wearer, never a fake promise (background vision, HFP+A2DP at once, App Store full-sensor photos).

- Package: `https://github.com/facebook/meta-wearables-dat-ios`
- Version pinned in this repo: **1.0.1** (9 October 2026). No developer-facing changes from 1.0.0.
- Docs: [wearables.developer.meta.com](https://wearables.developer.meta.com/docs/develop/dat/)
- Minimum phone: iOS 17.2. This app requires iOS 18.

Registration uses `Wearables.configure()`, `startRegistration()`, and `handleUrl` back from the Meta AI app. The Meta App ID, client token, and team ID come from the Wearables Developer Center and are build secrets, not source.

## v1 test glasses: Meta Glasses Adventurer

The owner calls his pair the **Adventurer**. That is a real product name.

| | |
| --- | --- |
| Product | **Meta Glasses Adventurer** |
| Brand | Meta's own frame. Not Ray-Ban. Not Oakley. Not Meta Ray-Ban Display. |
| Shape | Rectangular everyday sunglasses. Standard and Large. Also an Adventurer LISA edition. |
| Hardware | Same class as Ray-Ban Meta (Gen 2): 12 MP camera, open-ear speakers, microphone array, no in-lens display, no Neural Band. |
| DAT `DeviceType` | `metaGlasses` |
| Display? | No. `supportsDisplay` is false. |
| DAT support | **Yes.** Meta's hardware list includes "Meta glasses", and the 1.0.1 version table lists Meta glasses firmware **V128** next to Meta AI app **V292**. |

v1 proves three things on this pair: the phone hears the wearer over Bluetooth (HFP), the phone speaks back on the glasses speakers, and an explicit look grabs one camera photo. The camera is off the rest of the time.

Ray-Ban Meta, Ray-Ban Meta Optics, Oakley Meta HSTN, and Oakley Meta Vanguard are the same class of displayless glasses. They are supported, and they use the same audio-and-camera path. They are not the pair under test.

## What v1 uses

This is the standard build. It asks the least of the glasses and uses nothing Meta calls beta.

| Capability | Module | On Adventurer |
| --- | --- | --- |
| Pairing through the Meta AI app | MWDATCore | Yes |
| Device link, battery, worn, hinge, temperature | `Device.addDeviceStateListener` | Yes |
| Camera stream and a still photo | MWDATCamera | Yes, only when he asks the glasses to look, or turns live video on. 504 by 896 at 7 frames a second. |
| Microphone and speaker | Bluetooth HFP (mono 16 kHz mic + voice) or A2DP (speaker). **Not both at once.** HFP must settle before the camera stream. | Yes. The toolkit does not expose a separate speaker API. Phoenix Fox picks one link mode at a time. |
| In-lens display | MWDATDisplay | Not present. The app does not try to draw a card. |
| Inputs, motion, speech on the glasses | MWDATInputs, MWDATMotion, MWDATSpeech | Off. See the owner build below. |

## The owner build

One build setting, `PHOENIX_FOX_OWNER_BUILD`, decides which build this is. It is `NO` in the project and `YES` in the TestFlight workflow, so the build the owner installs from TestFlight is the owner build and a build made any other way is the standard one. The setting reaches the app as the Info.plist key `PhoenixFoxOwnerBuild`, and the workflow's signed-app check refuses to upload a build where the key is missing.

The owner build does two things.

1. **It switches every feature on once.** The accessibility suite, Guide mode's helpers, Smart Capture and its auto-route, memory ("mind meld"), the bot team, fast mode, and the glasses capabilities below. This happens the first time the build runs, and again only when a later build adds features. Anything the owner switches off stays off. **Settings → Owner build → Turn everything on again** repeats it by hand.
2. **It allows the parts of the toolkit Meta calls beta.** A standard build ignores those switches even if a settings file has them on.

Switching a feature on does not start it. The camera, a recording, Guide mode, and face enrollment still start only when asked. Guide mode still reads its safety notice before its first use, and saving a face still needs the wearer to say the person agreed.

The switches are under **Settings → Glasses → Glasses limits**.

### What the toolkit offers, and what Phoenix Fox uses

Everything here goes through the toolkit's public interface. Nothing changes the glasses' firmware, and the capture light is the glasses' own: it is on whenever the camera is, and Phoenix Fox has no way to change that and does not look for one.

| The toolkit offers | Limit | Owner build | Standard build |
| --- | --- | --- | --- |
| Video stream size | 360 by 640, 504 by 896, or 720 by 1280 | The largest size for one look, watching, Smart Capture, live video, and recordings. The middle size for Guide mode, where a fresh frame matters more than detail. | 504 by 896 |
| Video frame rate | 2, 7, 15, 24, or 30 a second. Any other number is refused. | 30 for a recording, 24 for Guide mode, 15 for live video, 7 where sharpness matters more than motion | 7 |
| Sound with the video | PCM at 16, 44.1, or 48 kHz from the glasses' microphones | 48 kHz as the sound track of a recording. 16 kHz for sound alerts while the camera is already on. | Not used |
| Photo from the whole sensor | Up to 4032 by 3024. Not while a stream is running. **Experimental in DAT** — Meta says apps that use it cannot ship to the App Store yet. | Owner / TestFlight only (`allowsExperimental` + Glasses limits). Falls back to a stream frame. | **Stream frame only** (App Store–safe). Full-sensor capture stays behind the owner flag. |
| HEVC stream | Compressed video in place of raw frames when the app is backgrounded. DAT does not decode these for third-party apps. | **Not used.** Raw frames only while foregrounded. | Not used |
| Touchpad and action button | Select, navigation, back | A double tap talks to Jarvis. A swipe back stops Jarvis talking. | Not used |
| Capture button | Short press, double press, hold | One press looks, two keep a picture, a hold takes a note | Not used |
| Neural Band | Select, navigation, drag | Listened for on display glasses, the pair a band comes with, and handled like the touchpad. Nothing waits on one. | Same |
| Motion | Head orientation and acceleration, 5 to 60 samples a second | 30 a second, used only to notice two nods or a shake. Nothing is stored or sent. | Not used |
| Speech on the glasses | Text from the glasses' own recognizer | Listens for the wake word when the phone's microphone is not listening | Not used |
| Display | Cards on the lens | Used when the glasses report a display. Adventurer has none. | Same |
| Device state | Link, battery, charging, worn, hinge, heat, compatibility | All read. Taking the glasses off ends the controls' session. Heat steps the stream down. | Read. Heat at the top level turns the camera off. |
| Session pause and stop from the glasses | Single tap pauses, long press stops | Followed. A paused session is waited on and never restarted. A session the wearer ends is not reopened until they next talk to Jarvis, put the glasses on, or reconnect. | Same, while the camera is on |
| Firmware and glasses-app update screens | `openFirmwareUpdate`, `openDATGlassesAppUpdate` | Two buttons under Settings → Glasses, and the session error that needs each one names it | Same |
| "Hey Meta" launch | `LaunchApp` voice invocation | Starts a Jarvis session | Same |
| Wi-Fi Aware pairing, file transfer | Types exist in the 1.0.1 interface | **Not used.** Meta's guides do not describe them, so there is no documented way to use them correctly. | Not used |

Each use of the camera gets its own stream, chosen in `StreamPlan.swift`. If the glasses refuse the larger stream, the basic one is tried before giving up. If a use that lasts (Guide mode, live video, a recording) finds the camera already on with a lesser stream, the camera is restarted with whatever the two uses need together, so the one that was running loses nothing. A recording in progress is never restarted.

### Heat

The glasses report five levels. From Meta's "moderate" level the frame rate is capped at 15. At "severe" it is 7 at the middle size, and sound is dropped from everything but a recording. At "critical" the camera is turned off and Jarvis says so. The stream only steps down. When the glasses cool, the next use gets the better stream.

### When the session is open

Opening a session for the controls has a cost the wearer can feel: while any app's session is open, the glasses keep **a single tap on the touchpad to pause that session** and **a long press to end it**. Those gestures stop doing what they normally do.

So on glasses without a display, Phoenix Fox holds a session only:

- while Jarvis is busy with the wearer, from the wake word until about twenty seconds after the answer,
- while the camera is on,
- and, if speech on the glasses is on, while the phone's microphone is not listening.

The rest of the time there is no session and the glasses behave as they always do. Display glasses keep the session while worn, because the lens cards need it.

This means the touchpad cannot start a conversation from nothing on Adventurer. An always-open session would allow it, and would take the single tap and the long press away all day. It is not built.

### Speech on the glasses

This is the one switch with an effect when Jarvis is not busy. It is on in the owner build because every feature is. Two things to know:

- It needs the glasses' microphone permission, which the Meta AI app grants. Phoenix Fox never opens Meta AI for this by itself. Use **Allow the glasses' microphone** on the Glasses limits screen once.
- For as long as the phone is not listening, its session holds the single tap and the long press as described above. If that is unwelcome, switch off **Speech on the glasses**. Nothing else depends on it.

Only a sentence that starts with the wake word is acted on, and only when the phone did not hear it too. Nothing the glasses hear is kept.

### Nods and shakes

A shake of the head says no to any question Jarvis is waiting on. With no question waiting it stops Jarvis talking, except during Guide mode and walking directions, where the head turns to look around.

Two nods say yes only to a question about the wearer's own lists: setting the emergency contact, or deleting a routine. A yes that calls someone, saves or erases a face, starts Guide mode, or lets an assistant act has to be spoken. A head moves for many reasons, and those answers cannot be taken back.


### Audio link modes (HFP vs A2DP)

Meta's mic and speaker path uses the phone's Bluetooth audio session. On the glasses:

- **HFP** carries the wearer's mic (mono **16 kHz**, tuned to their voice) and short spoken replies. Used while listening and for conversation.
- **A2DP** is higher-quality speaker output with **no** glasses mic. Used for longer playback when the mic is not needed.
- **They cannot run at the same time.** Phoenix Fox never enables both category options together (`AudioRoutePolicy` / `AudioSessionManager`).
- **HFP must be fully settled before the camera stream starts**, or glasses audio can fail with no error. `waitUntilCameraSafe()` enforces that ordering.

See [ON_DEVICE_CAPABILITIES.md](ON_DEVICE_CAPABILITIES.md).

### Why the HEVC stream is not used

Raw camera frames arrive only while Phoenix Fox is in the foreground. When the app is backgrounded or the phone is locked, the toolkit delivers HEVC-compressed frames that DAT does not decode for third-party apps — so a look while locked cannot work, and we refuse it with a spoken line. Recordings use raw frames with the phone unlocked; we do not promise background vision.

### How this was checked

GitHub Actions is the only compiler this project has, and it has not been able to run. Until it does:

- Every decision above (stream choice, heat, the double press, nods and shakes, which answers a head gesture may give, speech restarts, the wake-word gate, the owner profile) is plain Swift with unit tests that run on Linux.
- The code that calls the toolkit was type-checked on Linux, under strict concurrency with warnings as errors, against stand-ins generated from the toolkit's own interface files. That catches a wrong name, a wrong type, or a missing case. It does not show how the glasses behave.
- The SwiftUI screens and the voice session's changes were read, not compiled.
- **None of it has run on glasses.** Treat every owner-build capability as untested until the checks in [SETUP.md](../SETUP.md) pass.

## v2, not a launch blocker

Meta Ray-Ban Display and the Meta Neural Band are a different product (in-lens display, band in the box). The SDK can:

- Draw text cards with `Display.send` (`MWDATDisplay`) when `DeviceType.supportsDisplay` is true (`metaRayBanDisplay`).
- Deliver band input as semantic events (`select`, `nav`, `drag`) tagged `neuralBand` or `neuralBandDrag`. It does **not** give a third-party app the raw EMG waveform, and it does not document a distinct "pinch" event. A pinch shows up as a select or a nav, if the band is connected.

Phoenix Fox checks `supportsDisplay` before drawing anything, and it treats band events as optional. If either call fails, Jarvis keeps speaking. Adventurer never draws a card. Shipping v1 does not depend on Display hardware, a band, or the beta modules: with every switch on the Glasses limits screen off, the owner build behaves as the standard build does.
