# Design principles — presence, not Q&A

**North star:** the glasses should feel like they are experiencing and interacting with the world *with* the wearer — not a passive question box that only answers when poked.

Meta’s stock glasses features feel lame because they only react. Phoenix Fox is designed for **presence**: context-aware, timely, short, and collaborative. Jarvis shares what they saw and did together, notices place / time / motion / people when privacy allows, and keeps a consistent personality across every surface.

This document is binding for the current fix pass and every roadmap feature. Visual brand rules stay in [DESIGN.md](DESIGN.md). Hardware limits stay in [GLASSES_SDK.md](GLASSES_SDK.md) and [ON_DEVICE_CAPABILITIES.md](ON_DEVICE_CAPABILITIES.md).

## The test

Before shipping a feature, ask:

> If the wearer never said the wake word again for the next two minutes, would Jarvis still feel like a companion in the world with them — or like a silent gadget waiting for another command?

If the honest answer is the gadget, the feature is incomplete.

## Presence pillars

1. **With him, not at him.** Every look, nudge, and reply is framed as shared experience (“we’re looking at…”, “that’s the same corner as this morning”) rather than a detached caption service.
2. **Context before cloud.** Cheap on-device signals (time, place, motion, worn state, last scene labels, conversation window, focus) decide whether to speak. Paid models fill in only when presence needs richer language.
3. **Timely and short.** Proactive lines are one breath. They arrive when useful, not when the model finished thinking.
4. **Respect the Interrupt path.** Proactive speech yields to the wearer’s focus, Guide mode, walking directions, an open question, TTS in progress, and `shouldAllowInterrupt` / barge-in. Never talk over a hazard callout or a deliberate silence the wearer asked for.
5. **Live conversation window.** After Jarvis is awake, follow-ups do not need the wake word for a bounded conversation window (`conversationMode`). Ending the window is explicit (timeout, “stop”, glasses off, or the wearer leaving).
6. **Shared memory.** What they saw and did together stays available for follow-ups (encrypted notes, mind meld, last look summary, place notes). Memory is on-device by default and never exfiltrated without an ask.
7. **Place, time, motion, people — privacy-safe.** React to where / when / how he is moving, and to consented faces. Do not record, transcribe, or recognize bystanders without being told. Nothing listens to a room all day.
8. **One personality.** Jarvis is warm, direct, and under control — same voice across home, glasses, accessibility, and bots. Assistants (Fire Fox, Indy, Driver, Rally) keep their own names when speaking; Jarvis narrates the hand-off.
9. **Tunable, never spammy.** Every proactive channel has a switch and a quiet period. Defaults are conservative. “Off” means none of that channel’s code runs.
10. **Honest about limits.** Presence never fakes background vision, simultaneous HFP+A2DP, or App Store full-sensor photos. When the world cannot be sensed, say so in one short line.

## Proactive behavior rules

| Rule | Detail |
| --- | --- |
| On-device trigger | A nudge starts from a local signal (frame change, place enter, timer, worn, morning window, sound alert). Cloud may word the line; it must not be the alarm clock. |
| Cheap first | Prefer OCR, scene labels, motion, clocks, and stored notes over a vision or LLM call. |
| Interrupt manager | Before speaking, check focus / Guide / walking / open question / TTS / user “quiet”. If blocked, drop or defer — do not queue a pile. |
| One breath | Roughly ≤12 words unless the wearer asked for more (“go on”). |
| Quiet period | Each proactive kind has its own cooldown so the same nudge cannot repeat. |
| User tunable | Settings (or Workshop / Accessibility switches) can disable each kind. Owner profile may turn sensible defaults on; standard builds stay quieter. |
| Camera light | Any proactive look still turns the capture light on and only runs while the app can receive raw frames (foreground). |
| No spam | If the wearer dismisses or talks over a nudge twice, back off that channel for the session. |

## Conversation and memory

- **Wake word** opens presence; it is not required for every turn inside the live window.
- **Follow-ups** (“what about the price?”, “and the ingredients?”) reuse the last shared look or note without re-capturing when the scene is unchanged (`FrameChange`).
- **Remember / recall / mind meld / place notes** are first-class presence tools, not side features.
- **Bots** are teammates Jarvis brings in; they do not replace the sense that Jarvis was there for the look.

## Relationship to other docs

| Doc | How presence shows up |
| --- | --- |
| [DESIGN.md](DESIGN.md) | Phone UI: one glance for glasses / Jarvis / team; camera never a surprise. |
| [ON_DEVICE_CAPABILITIES.md](ON_DEVICE_CAPABILITIES.md) | Cheap local sensing is the default engine of presence. |
| [GLASSES_SDK.md](GLASSES_SDK.md) | Honest hardware limits so presence does not promise the impossible. |
| [FEATURE_PARITY.md](FEATURE_PARITY.md) | Meta parity is a floor; presence is how we beat reactive Meta AI. |
| [ACCESSIBILITY.md](ACCESSIBILITY.md) | Guide, captions, and callouts are presence under constraint — timely, interruptible, never spammy. |
| [LOOK_TO_TALK.md](LOOK_TO_TALK.md) | Looking selects a teammate; conversation continues without re-naming them. |
| [INNOVATION_BACKLOG.md](INNOVATION_BACKLOG.md) | New ideas must pass the presence checklist below or they stay on the shelf. |
| [SKILLS.md](SKILLS.md) | Skills may ask for a look or a place; they inherit interrupt and privacy rules. |

## Presence checklist (every feature)

Copy this block into a feature’s doc status section (or link here) and fill it before calling the feature Written or Built:

- [ ] **Shared experience** — Copy and behavior talk as “with you / we”, not a detached oracle.
- [ ] **Live follow-ups** — Inside the conversation window, no wake word for related turns; timeout / stop is clear.
- [ ] **Memory** — Relevant prior looks, notes, or place context are reused when safe; otherwise the feature says it does not remember.
- [ ] **Context signals** — Uses at least one of: time, place, motion, worn, last scene, focus — or documents why none apply.
- [ ] **Proactive path** — If it can nudge, the trigger is on-device, tunable, quiet-period gated, and Interrupt-aware.
- [ ] **Personality** — Jarvis (or the named bot) sounds consistent with the rest of the app.
- [ ] **Privacy** — No bystander capture/transcription/recognition without consent; camera light rules held.
- [ ] **On-device / cost** — Cheap local path first; cloud only when presence quality needs it ([ON_DEVICE_CAPABILITIES.md](ON_DEVICE_CAPABILITIES.md)).
- [ ] **Honesty** — Does not claim background vision, dual HFP+A2DP, or store-build full-sensor photos.
- [ ] **Anti-spam** — Defaults quiet; dismiss / talk-over backs off; Settings can disable.

## Anti-patterns (reject these)

- Silent wait for the next wake word while the wearer is clearly mid-task with Jarvis.
- Long monologues or stacked proactive speeches.
- Cloud round-trips to decide whether to say “you’re home” when Core Location already knows.
- Re-asking for context the pair just shared (“what are you looking at?” right after a look).
- Personality that flips between Settings screens, Guide mode, and bot hand-offs.
- Features that only exist as a button on the phone with no glasses presence path.

## Status of this north star

The principles are **binding now**. Many presence behaviors (conversation mode, morning brief, mind meld, place notes, Guide callouts, ambient captions) exist in code at partial strength. Treat gaps as product bugs against this document, not as optional polish.
