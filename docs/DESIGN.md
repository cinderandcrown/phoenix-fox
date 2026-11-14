# Design

How the Phoenix Fox iPhone app looks, moves, and speaks, and why. It covers the brand, the home screen, first run, the voice on the glasses, and the tests that keep them from drifting.

**Product north star** (presence with the wearer, not a passive Q&A box) lives in [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md). Every feature checklist must pass that document’s presence checklist. This file is the visual and interaction system for the phone UI.

## What has been checked, and how

No one on this project has a Mac, so read this section before trusting anything below.

| What | How it was checked |
| --- | --- |
| Every decision a screen makes: colors and their contrast, the live states, the orb's shape, the haptic cues, the team board, the onboarding steps, how a reply is shortened for speech, the picture comparison | Unit tests, run on Linux with strict concurrency and warnings as errors. They are in `OpenVisionTests` and also run on the simulator in CI. |
| The SwiftUI views for the home screen and first run | Type-checked on Linux against hand-written stand-ins for SwiftUI and UIKit. This catches a wrong name or type in our code. It does not prove the real SwiftUI accepts every line. Each SwiftUI call was also checked against Apple's documentation for its signature and the iOS version it needs. |
| The snapshot harness (`SnapshotHarness.swift`) | Parsed, and its UIKit calls checked against Apple's documentation. It has never run. |
| How any of it looks | Not checked. No simulator or phone has drawn these screens yet. There are no reference pictures in the repository. The first CI run that reaches the test step records them. |

CI is the only compiler. Until it runs this branch, treat the layout as a careful first draft.

## Principles

Presence and personality rules: [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md). For the phone UI specifically:

1. **The glasses are the product. The phone is the dashboard.** The wearer is usually not looking at the phone. So the home screen answers three questions at a glance: are my glasses there, what is Jarvis doing, and what is my team doing.
2. **Say what is happening in one or two words.** Listening. Looking. Asking Indy. Replying. A person should never wonder whether they were heard.
3. **The camera is never a surprise.** Red means the glasses camera is on, and nothing else in the app is red.
4. **Fire, kept under control.** The brand is warm and bright, but only one thing on a screen burns: the orb, or the one main button. Everything else is quiet ground and ink.
5. **Decisions are plain code with tests. Views only draw.** Each screen takes a plain value and can be drawn in any state without glasses, a relay, or a microphone.

## Brand

**The name.** The app is Phoenix Fox. Jarvis is the wake word and the voice. The screen says "Phoenix Fox" once, in the header, and "Jarvis" where it is the voice that is meant.

**The mark.** A fox's face whose ears are flames, with a pale blaze down the muzzle. It is drawn from one list of numbers in `FoxMarkGeometry.swift`. The app draws it with `FoxMark`, and `scripts/make_app_icon.py` reads the same numbers to draw the app icon, so the two cannot drift. Tests check that the mark is the same on both sides and stays inside its square. The code is Apache-2.0 like the rest of the app, but the name and the mark are reserved branding; see [NOTICE](../NOTICE).

**Type.** Headings are New York, the system serif, which gives the app a voice that is not the default. Body text is San Francisco. Both come only from text styles (`Theme.display(.title)`, `.font(.body)`), never from fixed sizes, so every word follows the Dynamic Type setting.

**Shape.** Cards have a 22-point continuous corner, chips 12. Spacing is on a four-point grid: 4, 8, 12, 16, 24, 32. Anything that can be tapped is at least 44 points on each side.

## Color

Colors are numbers in `BrandPalette.swift`. `Theme` turns them into SwiftUI colors that follow light and dark mode. The app follows the system setting; it no longer forces dark mode.

| Name | Light | Dark | Used for |
| --- | --- | --- | --- |
| ember | `#FF5A1F` | same | The brand color, as a fill |
| flame | `#FF8A1F` | same | The top of the main button, the orb |
| gold | `#FFC247` | same | The hot core of the orb, highlights |
| garnet | `#A61B1B` | same | The deep edge of the orb and the mark |
| onFire | `#1F0D05` | same | Words on an ember, flame, or gold fill |
| canvas | `#FBF5EE` | `#0D0A09` | The screen behind everything |
| surface | `#FFFFFF` | `#1A1412` | Cards |
| raised | `#F4EAE0` | `#251C19` | A quiet button, an unlit monogram |
| ink | `#1E1410` | `#FFF6ED` | Main text |
| inkSoft | `#655246` | `#CBB9AB` | Secondary text |
| inkFaint | `#7A675B` | `#9C8A7D` | Captions and timestamps |
| emberInk | `#B5380A` | `#FF7A3D` | The brand color where it must be read: links, symbols, the tint |
| goldInk | `#8A5A00` | `#FFC247` | Warnings |
| seeing | `#C4221A` | `#FF5A52` | The camera is on |
| onSeeing | `#FFFFFF` | `#1F0D05` | Words on the camera banner |
| good | `#1E7A45` | `#5BD68A` | Done, connected, allowed |

The grounds are warm, not gray: parchment by day and a brown-black by night.

**Contrast is a test, not a promise.** `BrandPaletteTests` computes the WCAG contrast ratio for every ink on every ground, in light and in dark, and fails if any text pairing is under 4.5 to 1. The lowest pairings today are inkFaint and good on the raised ground in light mode, at 4.5 to 1. Main text is above 15 to 1 everywhere.

Two decisions came out of those numbers:

- **Words on the ember button are dark, not white.** White on ember is 3.1 to 1 and fails. The dark label is 6.0 to 1. A test keeps this from being "fixed" later.
- **The brand color has a second, darker form for text.** Ember itself is too light to read on parchment, so links and symbols use emberInk.

With Increase Contrast on, caption text uses the soft ink.

**Color is never the only signal.** Every status also has its own symbol and its own words.

## Materials

On iOS 26 the system draws tab bars, navigation bars, and sheets in Liquid Glass. The app uses the system's own tab bar and sheets and does not restyle them, so it gets that look, and its behavior under Reduce Transparency and Increase Contrast, for free.

Our own use of glass is one rule: **glass is for a control that floats over content, never for content.** The glasses chip in the header is glass (`floatingGlass`, which is `glassEffect` on iOS 26 and the system material on iOS 18). Cards are solid, so text on them always has the contrast the tests promise.

## The home screen

`HomeContent` draws it from a `HomeModel`. `VoiceAgentView` fills the model in from the running app. From the top:

1. **Header.** The mark, the name, a record button when glasses are connected, and the glasses chip: "Connect glasses", "Glasses away", "Glasses ready", or "Camera on". A tap opens the glasses settings. At large text sizes the name gives way so the chip always fits.
2. **The stage.** The orb, one or two words for what Jarvis is doing, and one line of help. The whole stage is one button.
3. **What is happening.** Shown only when there is something to show: the camera banner, a saved recording, the open document, live captions, and the last thing you said with the last answer.
4. **Your team.** A card for each assistant, or a card that offers to connect them, or the name of the other AI that is answering.

Trouble appears as a banner at the bottom, in words, with a button to dismiss it. The screen scrolls, so nothing is cut off at the largest text sizes.

### Live states

`LivePhase` reduces everything the app knows to one phase. It is plain code with tests.

| Phase | Title | Line under it | Orb | A tap |
| --- | --- | --- | --- | --- |
| Loading the voice model | Getting ready | Loading the voice on this phone. | Resting | Starts a conversation |
| Waiting | Ready | Say "Jarvis" or tap. | Resting | Starts a conversation |
| Connecting | Waking up | One moment. | Thinking | Ends the conversation |
| Hearing you | Listening | Go ahead. | Listening | Ends the conversation |
| Thinking about what the camera shows | Looking | Through your glasses. | Thinking, with a red ring | Ends the conversation |
| Thinking | Thinking | One moment. | Thinking | Ends the conversation |
| An assistant has the question | Asking Indy | Waiting for the answer. | Thinking | Ends the conversation |
| A tool is running | Working | The tool's name | Thinking | Ends the conversation |
| Speaking | Replying | Say "Jarvis, stop" or tap. | Replying | Stops the answer and listens again |
| Live video | Live video | Say "stop video" to end. | Replying | Ends the conversation |

The wake word in these lines is the one the owner chose.

**Seeing** is shown several ways at once, because it matters most: a red ring is drawn around the orb, the glasses chip says "Camera on", a red banner says "Camera on. The capture light on your glasses is lit.", and the title says "Looking" while Jarvis is thinking about what it sees. The ring, the chip, and the banner follow the camera itself and not the phase, so they also show whenever the glasses are streaming for another reason, such as Guide mode.

### The orb

The orb is a coal. `EmberGeometry` works out its outline from a few sine waves, and `EmberOrb` draws it thirty times a second in three layers: a blurred glow, the body, and a core that goes from gold toward white as it heats.

| Mood | How it moves |
| --- | --- |
| Resting | Slow, shallow breathing. Dim. |
| Listening | Larger, almost round, bright and steady. It is paying attention, so it holds still. |
| Thinking | Fast small ripples around the edge. |
| Replying | Broad slow swells, as if speaking. |

A change of mood blends over 0.45 seconds. Tests check that the outline never leaves its square in any mood, that it closes, that the four moods are different shapes, and that a change of mood never makes the outline jump.

With Reduce Motion on, the orb holds still and only its shape and brightness change between moods.

### Your team

`TeamBoard` records what each assistant is doing as requests go out and answers come back through the relay: ready, working on a task and for how long, answered, sent an alert, or failed and why. A card shows the assistant's initials on a coal that lights while it works, its name, and one line. A tap opens a sheet with what it is doing now, a sentence to try saying to it, and its recent activity.

The board is kept in memory while the app is open. It is not saved. Whole conversations are in History.

### Haptics

The phone is often in a pocket, so the beats of a turn can be felt. `HapticCue` decides which moments get one, and the rules are tested.

| Moment | Feel |
| --- | --- |
| Jarvis started listening | A medium tap |
| Jarvis heard the request and took it | A selection tick |
| The answer started | A soft tap |
| The glasses camera came on | A rigid tap |
| An assistant answered while Jarvis was quiet | Success |
| An urgent alert | Warning |
| Something went wrong | Error |

Going back to rest is silent. So is the microphone reopening after an answer, and the camera turning off. These use the system's feedback generators, so they follow the phone's own haptic settings.

### Motion

Three timings, in `Theme.Motion`: a state changing (0.35 seconds, smooth), something answering a touch (0.2 seconds, snappy), and a card or screen arriving (a soft spring). Things fade and settle; nothing bounces. Under Reduce Motion the orb holds still, the status symbol stops pulsing, buttons do not shrink when pressed, and the banners fade in without sliding or scaling. Cards still settle into place when something above them appears.

## First run

Five steps, one at a time, each with one main button. There is no swiping between pages, so it works the same with VoiceOver and Switch Control as with a thumb. `OnboardingFlow` holds the words and the rules, with tests.

| Step | What it does | Can be skipped |
| --- | --- | --- |
| 1. Meet Jarvis | Says what the app is in three short points. | No, it is one tap |
| 2. Connect your glasses | Says what the Meta AI app is about to ask, then opens it. | "I'll do this later" |
| 3. Let Jarvis hear you | Explains three permissions, then asks for them. | "Not now" |
| 4. Connect your assistants | Takes the relay address and token and tests them. | "Skip, I don't have a relay" |
| 5. You're set | A checklist of what is ready and what was left, and a sentence to say first. | |

The rules:

- **Every step with something to set up can be skipped.** Someone whose glasses are still in the post can look around.
- **The reason comes before the question.** Each permission has one or two sentences on the screen before iOS shows its own prompt, and each starts with what it is for: "So Jarvis can hear you through your glasses."
- **Only three permissions are asked for up front**: microphone, speech recognition, and notifications. Location, Photos, Contacts, and the rest are asked for the first time a feature needs them.
- **A "no" is respected and explained.** A denied permission shows "Turned off. You can turn it on in the Settings app." with a button that opens Settings. The app does not ask again or block.
- **Plain words.** A test fails if the steps use words such as "register", "authenticate", "endpoint", or "backend".
- **The glasses step makes the privacy promise** where it belongs: the camera is used only when you ask Jarvis to look, the capture light is on whenever the camera is, and Phoenix Fox cannot turn that light off.
- **Nobody ends on a dead end.** If the relay is set up, your assistants answer. If you had already chosen another AI and it works, it is left alone. If nothing is set up, the app starts on the AI built into the phone when the phone has it. If it does not, the last step says so in plain words and points to Settings.
- **The step is remembered.** Leaving for Meta AI or Settings and coming back does not start over.

Someone who finished the old onboarding does not see the new one.

## Voice on the glasses

A reply on the glasses is heard once, in order, often while walking. So:

- **A quick word back, first.** As soon as a request for an assistant is understood, Jarvis says a short line before anything slow happens: "Asking Indy.", "Asking everyone.", "Taking a look." when a photo is going with it, or one of "On it.", "One moment.", "Right away." in turn. It is spoken before the photo is taken, not after.
- **Plain words only.** Text written by a model is cleaned before it is spoken: no markup, no bullets or headings, no emoji, a link becomes its words, and a bare web address becomes the site's name. Text read aloud for a blind wearer, such as a sign or a document, is not altered.
- **Short first, more on request.** With "Short spoken replies" on, which is the default, an assistant's long answer is cut at a sentence end after about 70 words, roughly half a minute, and ends with "There's more. Say go on." Saying "go on", "continue", "keep going", or "read the rest" speaks the next part. Any other request drops the rest. An answer that is only a little over the limit is spoken whole. The whole answer is always in History.
- **The persona asks for the same thing**: lead with the answer, one to three short sentences, no lists, and offer more in a few words when there is more.
- **Easy to stop.** While Jarvis is talking, "Jarvis, stop" stops it, "Jarvis" followed by a new request replaces it, and a tap on the orb stops it and listens again. In the owner build with Nod and shake on, a shake of the head stops it too. Speech without the wake word does not interrupt, on purpose: the microphone also hears the answer, and treating any sound as an interruption cut answers off.

`SpokenReplyTests` covers the cleaning, the cutting, and "go on".

## Accessibility

- **VoiceOver.** The stage is one element named "Jarvis". Its value is the phase and the line under it, plus "The camera on your glasses is on." when it is, and its hint says what a double tap will do. Each team card is one element that says the name, the status, and how long it has been working. Decorative pictures are hidden. Headings are marked as headings.
- **The phase is not announced when it changes.** This is deliberate. An announcement plays through the phone's speaker, and the microphone listening for the wake word would hear it. Sound cues on the glasses and haptics on the phone mark the changes. The stage is marked as updating often, so VoiceOver reads the current state whenever it is touched.
- **First run** moves VoiceOver to each step's title when the step appears, and each permission is read as one sentence: its name, your answer, and the reason.
- **Dynamic Type.** All text uses text styles. Screens scroll. The header drops the name before it squeezes the glasses chip. The monogram grows with the text.
- **Reduce Motion, Increase Contrast, light and dark** are described in the sections above.
- **Not done:** the Settings and History screens were not redesigned in this pass. They are system lists, so they already follow Dynamic Type, VoiceOver, and light and dark mode, and they pick up the new tint.

[ACCESSIBILITY.md](ACCESSIBILITY.md) covers the features built for blind, low-vision, Deaf, and hard-of-hearing wearers.

## Previews

Every new view file has SwiftUI previews, including ones in light mode and at the largest text size. They are for anyone who opens the project in Xcode.

`HomeSamples` holds seven made-up states of the home screen: first launch, ready, listening, seeing, asking Indy, replying, and trouble. `OnboardingSamples` holds each step part-way through. Previews and snapshot tests draw the same samples. Both are compiled into debug builds only, so none of the made-up text ships.

## Snapshot tests

A snapshot test draws a screen to a picture and compares it with a reference picture in the repository. If a change moves something, the test fails and shows what moved.

**What is drawn.** Each of the seven home screen samples and each of the five onboarding steps, three ways: dark, light, and dark at an accessibility text size. That is 36 pictures, each 390 by 844 points at two pixels per point.

**How.** `SnapshotHarness` puts the view in a window with no safe area, so the simulator model does not move the layout, draws it with UIKit, and hands the pixels to `PixelDiff`. There is no third-party library.

**What counts as the same.** A pixel matches if no channel is more than 8 of 255 away from the reference. A picture matches if no more than one pixel in five hundred is outside that. A moved line of text is far more than that; a slightly different rounding of a few edges is less. These are starting values with no history behind them. Tighten them once the pictures have proved stable.

**References are kept per iOS version**, in `OpenVisionTests/__Snapshots__/ios26/`, because each version draws text and materials a little differently. A new major version starts a new folder.

### Recording the first references

There are none yet. When a reference is missing, the test records the picture in its place, checks only that it is the right size and that something was drawn, and passes. CI then:

1. Uploads `OpenVisionTests/__Snapshots__` as an artifact named `snapshots`.
2. Shows a warning on the run saying how many pictures were recorded.

To commit them, from any machine with the GitHub CLI:

```bash
gh run download <run-id> --name snapshots --dir OpenVisionTests/__Snapshots__
git add OpenVisionTests/__Snapshots__
git commit -m "Snapshots: record references"
```

Look at the pictures before committing them. A reference is a statement that this is how the screen should look, and the first set has never been seen by anyone.

### When a snapshot test fails

The failure message says how many pixels changed. The `snapshots` artifact holds a `failed` folder with two pictures for each failure: `name.actual.png` is what was drawn, and `name.changed.png` is the reference, faded, with every changed pixel in magenta. Both are also attached to the test result.

- If the change was not meant, fix the code.
- If it was meant, replace the reference with the `actual` picture and commit it.

The `failed` folder is ignored by git.

### Three tests that need no reference

These mean something from the first run:

- The same screen drawn twice gives the same picture. If this fails, something on the screen moves on its own and no reference would ever match.
- Light mode and dark mode give different pictures.
- The large text size gives a different picture.

## Where the code is

| What | Where |
| --- | --- |
| Colors and contrast rules | `OpenVision/Views/Design/Core/BrandPalette.swift` |
| SwiftUI colors, type, spacing, motion, buttons | `OpenVision/Views/Components/Theme.swift` |
| The mark and the icon | `Views/Design/Core/FoxMarkGeometry.swift`, `Views/Design/FoxMark.swift`, `scripts/make_app_icon.py` |
| Live states, glasses chip, haptic cues | `Views/Design/Core/LivePhase.swift`, `Views/Design/HapticCue+Play.swift` |
| The orb | `Views/Design/Core/EmberGeometry.swift`, `Views/Design/EmberOrb.swift` |
| Home screen | `Views/Home/`, filled in by `Views/VoiceAgent/VoiceAgentView.swift` |
| Team board | `Services/Brain/TeamBoard.swift`, `TeamBoardStore.swift` |
| First run | `Views/Onboarding/` |
| Spoken replies and the quick word back | `Services/Brain/SpokenReply.swift`, `PhoenixFoxTurn.swift` |
| Snapshot tests | `OpenVisionTests/PixelDiff.swift`, `SnapshotHarness.swift`, `DesignSnapshotTests.swift` |

## Not done yet

- Nothing here has been seen on a screen. The first job after CI runs is to look at the recorded pictures and fix what is wrong.
- Settings and History keep their system-list look.
- The team board is not saved between launches.
- Each assistant has a monogram, not its own color or picture.
- There is no widget or Live Activity layout, which needs an app extension.
- The app icon has one appearance. iOS 18 and later can also take dark and tinted versions.
