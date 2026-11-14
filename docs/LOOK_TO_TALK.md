# Look to Talk

Looking chooses an assistant, and the voice does the rest. You look at an assistant's chat window on your computer, the glasses camera sees it, and what you say next goes to that assistant without saying its name.

This is a core **presence** feature: looking selects a teammate, then conversation continues without re-naming them — experiencing the desk *with* the wearer. It must pass the [presence checklist](DESIGN_PRINCIPLES.md#presence-checklist-every-feature).

**Status: written, owner build.** The owner profile turns Look to Talk **on** by default in owner / TestFlight builds; the Workshop switch can still turn it off, and with the switch off none of its commands match. The rules are covered by unit tests that run on Linux, and the code that joins them to the camera and the voice turn was type-checked on Linux against stand-ins. It has not been confirmed on glasses yet.

## Presence checklist

- [x] Shared experience — looking locks a teammate; Jarvis narrates the hand-off.
- [x] Live follow-ups — while held, requests need no assistant name (conversation continues).
- [x] Memory — lock persists across looks-away until “let go” or idle timeout.
- [x] Context — camera + on-device OCR/QR; no cloud required to choose.
- [x] Proactive — confirmation tone + short “Indy, locked.”; Interrupt-aware via existing voice path.
- [x] Personality — Jarvis speaks the lock; the named bot answers the work.
- [x] Privacy — frames read on-device and dropped; capture light on while looking.
- [x] On-device / cost — selection is local; only the ask may hit the relay.
- [x] Honesty — does not claim eye tracking; head direction only.
- [ ] Anti-spam / hardware — quiet defaults verified on Adventurer (not yet run on glasses).

## Using it

1. Turn it on in **Settings → Owner build → Workshop → Look to Talk**. The assistants must be connected through the relay.
2. Say **"look to talk"**. Jarvis says the camera light is on.
3. Look at an assistant's chat window. Hold still for about two seconds.
4. You hear three rising notes and "Indy, locked." The camera goes off, and the microphone opens for your request as if you had said the wake word.
5. Say the request. It goes to Indy. So does the next one, and the one after, until you say **"let go"** or the lock goes unused for ten minutes.

| Say | What happens |
| --- | --- |
| "Look to talk" | The camera comes on and looks for an assistant's window. |
| "Lock on" | Holds the assistant in view, so you can look away. Only needed when automatic lock is off. |
| "Lock on to Indy", "switch to Driver", "talk to Rally" | Chooses an assistant by name. The camera is not used. |
| "Look again" | Looks for another window. The lock you have is kept until another is found. |
| "Who am I talking to?" | Says who is held. |
| "Let go", "unlock", "stop look to talk" | Lets go, and turns the camera off if Look to Talk turned it on. |
| "Ask this one to check the build" | With nothing held: takes one look, sends that one request, and holds nothing afterwards. With an assistant held, "this one" is that assistant and the camera is not used. |
| "Look at this" | While an assistant is held, sends it a photo of what you are looking at. |
| "Yes", "no", or a name | Answers "Talking to Indy?" |

While an assistant is held, a name said aloud still wins: "ask Driver to check the gate" goes to Driver, and the lock stays on Indy. Commands the phone answers itself, such as the time or a timer, are still answered by the phone. "Status report" still goes to everyone.

## How it decides

The phone reads each frame for text and for QR codes. Three things can say which assistant a window belongs to, strongest first.

1. **A marker.** A QR code whose text is `PFX:BOT:` and the name, such as `PFX:BOT:INDY`.
2. **A badge.** A line that reads `TALK TO INDY`, or `LOOK TO TALK INDY`, and nothing else. It may wrap onto two lines.
3. **The name as a title.** The name alone on a line, or in a short line such as "Indy - Grok".

A name inside a sentence counts for little. "I'll pass this to Indy", read in Driver's window, does not move the target to Indy. "Firefox", written as the browser writes it, is not the assistant Fire Fox. "FireFox" and "fire_fox" are.

The glasses camera points where your head points, not where your eyes do. What is nearest the middle of the frame, left to right, is taken as what you are facing. Height counts for much less, because a window's title is above where you look.

One look is not a choice. A target is taken when two looks in a row agree, about two seconds, or when one look finds a marker or a badge. When the looks agree and are still not clear, because the name was faint or two windows are equally near the middle, Jarvis asks once: **"Talking to Indy?"** Say yes, no, or the right name. Where head gestures are on, a nod or a shake also answers. If you say no, that window is left alone for 45 seconds and the next best one is offered. If you say nothing, the question is dropped and not repeated.

"Ask this one to…" is stricter, because a request sent to the wrong assistant cannot be taken back. When that look is not clear, Jarvis asks "Send that to Indy? Say yes or no." The yes has to be spoken. A nod is not enough, and a shake still says no.

## What is held, and for how long

- **Locked** is the default. The assistant is held until you let go, and the camera is off. A lock that is not used for ten minutes ends by itself, with two falling notes, so that something you say an hour later does not go to an assistant you chose for something else. Each request sent to the assistant starts the ten minutes again. The time can be set from 1 to 60 minutes.
- **Followed** is what you get with "Lock on, and turn the camera off" switched off. The assistant is held while its window stays in view, and looking at another window moves the target. The camera stays on, so the capture light stays on. After five seconds out of view the assistant is let go. After five minutes it is locked anyway, to save the battery.

The search gives up after 45 seconds without a window, says so, and turns the camera off.

## Where requests go

A held assistant changes one thing in the turn: a request that names nobody goes to it, through the relay, instead of to the default assistant. It is never answered by the quick model on the phone, because you are talking to that assistant. If another AI is chosen as the brain in Settings, a held assistant still gets the request.

While Look to Talk is looking or holding an assistant, the home screen shows a row saying so, with a button that lets go.

Replies are spoken as they always are, with the assistant's name in front unless it is the default one. On glasses with a display, each reply and each Look to Talk line is also sent to the lens as a card through the same code every other reply uses. That path has not been run on display glasses.

## Tones

The glasses have no vibration, so a choice made by looking is confirmed in the ear.

| Tone | Shape |
| --- | --- |
| Found | Two rising notes |
| Locked | Three rising notes, ending an octave up |
| Let go | Two falling notes |
| Not sure | A small step up that slides, like a question |

Each assistant has its own starting note, by its place on the roster, from C5 upwards. A sixth assistant shares the first one's note.

## The camera and privacy

- With the settings as they come, the camera is on only between "look to talk" and the lock, or the 45-second limit. The capture light is on the whole time, and Jarvis says so when it starts. "Ask this one to…", said with nothing held, turns the camera on for up to six seconds. The light shows it, and Jarvis does not announce it.
- Frames are read on the phone with Apple's Vision framework and dropped. None is saved, and none is sent to an assistant, the relay, or anyone else. Only "look at this" sends a photo, as it always has, and only when you say it.
- What the phone reads off the screen is used to find a name and then discarded. It is not kept in the conversation history.
- Other people's screens are read the same way if you look at them while it is searching. Nothing is kept, and the only thing that can come of it is a wrong guess, which the question and the 45-second rest are there for.
- If Guide mode, watch, Smart Capture, live video, or a recording is using the camera, Look to Talk shares it and leaves it on when it finishes.

## Making a window easy to find

A window's title is small. The stream from the glasses is 720 by 1280 pixels when the owner build's full-rate video is on and 504 by 896 when it is not, and from an ordinary sitting distance that is probably too coarse to read a title bar. These help, most reliable first:

1. **A marker.** Settings → Look to Talk → Badge and marker shows a QR code for each assistant. Share it to your computer and keep it open beside the window, four centimetres across or larger.
2. **A badge.** Save [look-to-talk-badge.html](look-to-talk-badge.html) to your computer and open it with the name after a `#`, such as `look-to-talk-badge.html#Indy`. It is one file that loads nothing and sends nothing. A sticky note or a paper label with the same words works too. Aim for letters about two centimetres tall.
3. **Zoom the chat window** so the assistant's name is large.
4. **Other names.** If the window shows a handle instead of the roster name, add it under "Names on the screen".
5. **"Lock on to Indy"** needs no camera at all.

## What is not known, and what is not built

- **Whether a title can be read at all.** The estimate is that letters need to be about two centimetres tall at 60 centimetres. That number comes from the stream size and an assumed field of view, not from a measurement. It may be better or worse on the Adventurer.
- **How far off the camera is from your gaze.** It sits at the temple and points where the head points. Two windows side by side on one screen may be too close to tell apart, which is what the question is for.
- **Glare, dark mode, and small fonts** have not been tried.
- **The whole-sensor photo**, which is much sharper than the stream, is not used. It cannot be taken while the stream runs. It is the obvious next step if titles turn out unreadable.
- **Avatars are not recognized.** Only text and QR codes are.
- **A lasting "locked on" mark on the lens** is not built. The spoken lines are sent as cards and that is all.
- **The thresholds** (what counts as clear, how many looks, how long each wait is) were chosen by reasoning and are covered by tests, but none has been tuned on real frames.
- **A Neural Band pinch to lock** is not built.

### What to try first on the glasses

1. With a badge on screen: "look to talk", look at it. Expect a lock within about two seconds.
2. With a marker instead. Then with neither, the window zoomed until the name is large.
3. Two windows side by side. Expect the question.
4. Lock on, look away, ask something. Check it went to the right assistant, and that the camera light is off.
5. "Ask this one to say hello", with nothing locked.
6. Leave it searching at a blank wall. Expect it to give up at 45 seconds and the light to go off.

## Adding another kind of target

The feature is built so that an assistant's window is only the first kind of thing that can be chosen by looking. A document, a browser tab, or a shop's order page would be added like this:

1. A new case in `LookTarget.Kind`.
2. A reader that finds it in a `ScreenView`, which is the text and codes of one frame with their positions. `WindowReader` is the one for assistants. A marker for a page could be `PFX:DOC:` and an id.
3. A decision about what holding it means. For a page it is most likely "this is the context for my next request", sent to the assistant already held, not "talk to this".

The tracker, the tones, the spoken commands, and the settings do not know which kind they are handling. "Look at this" with an assistant held already sends a photo of whatever is in view to that assistant, and that is the bridge to these.

## Who else

- Meta has a published patent application, [WO2023091403A2](https://patents.google.com/patent/WO2023091403A2/en), that describes glasses with eye tracking working out which of several assistants on their display the wearer is speaking to from the direction of their gaze. Look to Talk uses the outward camera and reads a separate computer's screen, and it follows the head, not the eyes. Whether that application matters to this feature is a question for a lawyer, and it should be asked before the feature is described as new or offered outside the owner build.
- [Vergance](https://github.com/Tatendaz/Vergance) is a desktop tool that uses a webcam to track the eyes and resolves "this" to an element on screen.
- Apple Vision Pro uses the eyes to point and a pinch to act.
- Other glasses assistants that reach several agents, such as the Even Realities companion apps, choose by a spoken name. No shipped product was found that chooses an assistant by looking at its window through camera glasses. One search was made, and it was not exhaustive.

## Where the code is

| Part | File |
| --- | --- |
| Targets, what a frame holds, the verdict | `OpenVision/Services/LookToTalk/Core/LookTarget.swift` |
| Names, badges, markers | `OpenVision/Services/LookToTalk/Core/WindowReader.swift` |
| Dwell, asking, following, locking | `OpenVision/Services/LookToTalk/Core/LookTracker.swift` |
| One look for one request | `OpenVision/Services/LookToTalk/Core/LookOnce.swift` |
| Spoken commands | `OpenVision/Services/LookToTalk/Core/LookCommand.swift` |
| Tones | `OpenVision/Services/LookToTalk/Core/LookTone.swift` |
| Camera loop, tones, sharing the camera | `OpenVision/Services/LookToTalk/LookToTalk.swift` |
| Reading a frame on the phone | `OpenVision/Services/Accessibility/AccessVision.swift` (`screen(in:)`) |
| Routing to the held assistant | `OpenVision/Services/Brain/FastModeRouter.swift` (`focus`) |
| Settings, badges, markers | `OpenVision/Views/Settings/LookToTalkSettingsView.swift`, `LookBadgeImage.swift` |
| Home screen row | `OpenVision/Views/Home/HomeContent.swift` (`LookRow`) |
| Tests | `OpenVisionTests/LookToTalkReadingTests.swift`, `OpenVisionTests/LookToTalkTrackerTests.swift` |
