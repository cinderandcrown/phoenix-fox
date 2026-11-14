# Glasses and the official toolkit

Phoenix Fox talks to the glasses only through Meta's Wearables Device Access Toolkit for iOS. The wearer says Jarvis. That is the wake word, not the product name.

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

| Capability | Module | On Adventurer |
| --- | --- | --- |
| Pairing through the Meta AI app | MWDATCore | Yes |
| Device link, battery, worn, hinge, temperature | `Device.addDeviceStateListener` | Yes |
| Camera stream and a still photo | MWDATCamera | Yes, only when he asks the glasses to look, or turns live video on |
| Microphone and speaker | Bluetooth HFP and A2DP, as Meta's mic and speaker guide describes | Yes. The toolkit does not expose a separate speaker API. |
| In-lens display | MWDATDisplay | Not present. The app does not try to draw a card. |
| Neural Band EMG | MWDATInputs sources `neuralBand` and `neuralBandDrag` | Not part of this product. Temple-pad taps can still arrive as ordinary input. Nothing waits on a band. |
| On-glasses speech, motion | MWDATSpeech, MWDATMotion | Present in the SDK as experimental. Switches in Settings default off. v1 uses the phone's speech recognizer and does not upload motion. |

## v2, not a launch blocker

Meta Ray-Ban Display and the Meta Neural Band are a different product (in-lens display, band in the box). The SDK can:

- Draw text cards with `Display.send` (`MWDATDisplay`) when `DeviceType.supportsDisplay` is true (`metaRayBanDisplay`).
- Deliver band input as semantic events (`select`, `nav`, `drag`) tagged `neuralBand` or `neuralBandDrag`. It does **not** give a third-party app the raw EMG waveform, and it does not document a distinct "pinch" event. A pinch shows up as a select or a nav, if the band is connected.

Phoenix Fox checks `supportsDisplay` before drawing anything, and it treats band events as optional. If either call fails, Jarvis keeps speaking. Adventurer never enters that path. Shipping v1 does not depend on Display hardware, a band, or those experimental modules being allowed in a public build.
