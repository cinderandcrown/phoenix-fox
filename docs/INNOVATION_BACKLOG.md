# Innovation backlog

Ideas for what Phoenix Fox could do with a pair of Meta glasses and a team of assistants, scored, with ten of them chosen to build.

Two things to know before reading it.

**Most single ideas already exist somewhere.** A short search before writing this found shipped products for an ear prompter, voice flashcards, medication logs, and "what did I promise Dana". They are named in the tables and in [Who else is building](#who-else-is-building). The search was brief, so "not found" below means only that. What nobody else has is the combination this app is built on: a camera on your face, a team of assistants that can act, a nod and a shake as input, and rules about the capture light that are never bent. The ideas that need all of that are the ones worth building first.

**Presence is the filter.** An idea that only adds another wake-word Q&A does not ship. Every chosen feature must pass the [presence checklist](DESIGN_PRINCIPLES.md#presence-checklist-every-feature) in [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md): with the wearer, context-aware, Interrupt-respecting, memory of what they saw/did, tunable proactive nudges, consistent personality.

**Nothing in this file has run on glasses.** The ten chosen ideas are written and unit-tested. Their status is at the end of [The ten](#the-ten).

## What there is to work with

| The glasses give us | Limit | Used for |
| --- | --- | --- |
| Camera stream | Up to 720 by 1280 at 30 frames a second. The capture light is on. | Watching, guiding, recording |
| Whole-sensor photo | 4032 by 3024. Not while a stream runs. The capture light is on. | Small print: labels, ingredients, model plates |
| Microphones | Hands-free audio to the phone. The glasses' own room sound only while the camera is on. | Voice, captions, sound alerts |
| Speakers | Open-ear, heard by the wearer | Every answer |
| Touchpad, capture button | Only while a session is open, which is only while Phoenix is busy with the wearer | Talk, stop, look, keep, note |
| Head motion | 5 to 60 readings a second, only while a session is open | A shake for no. Two nods for yes, where a spoken yes is not required. |
| Worn or not, hinge, battery, heat | Always, while the app runs | Automations, warnings |
| Lens display, Neural Band | Not on Adventurer. Display glasses only. | Later: cards, lists, a pinch |

The phone adds text recognition, barcodes, sound recognition, speech, translation, location, and sealed storage, all without a network.

The assistants (Fire Fox, Indy, Driver, Rally) are reached through the relay. They can be asked one at a time or all together, they can be sent photos, and they can push a message back to the glasses.

## Rules that do not bend

1. The camera runs only when the wearer asks, and the capture light is on whenever it runs.
2. Other people are not recorded, transcribed, or recognized without being told. Nothing listens to a room all day.
3. Anything with a number in it (a dose, a price, an ingredient) is read from the text, not described by a model, and the wearer hears the words that were read.
4. A feature that protects someone says what it could not read. It never says "safe".
5. Health data stays on the phone, sealed, and is not sent to an assistant.
6. An assistant acts for the wearer only after a spoken yes.
7. A plugin cannot run code on the phone or name an address to send things to. It can only ask the wearer's own assistants.
8. Presence rules in [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md) are binding: on-device triggers for proactive lines, Interrupt respect, no spam, shared memory, consistent Phoenix personality.

### Presence checklist (each backlog feature before Written → Built)

- [ ] Shared experience with the wearer (not a passive Q&A bolt-on)
- [ ] Live follow-ups in the conversation window without re-waking
- [ ] Remembers what they saw/did together when relevant
- [ ] Uses place / time / motion / people only when privacy-safe
- [ ] Any nudge is on-device-triggered, tunable, quiet-period gated, Interrupt-aware
- [ ] Consistent personality; honest about DAT / offline limits
- [ ] Full list: [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md#presence-checklist-every-feature)

## How ideas are scored

Each score is 1 to 5, and 5 is always the good end.

| Column | 5 means | 1 means |
| --- | --- | --- |
| **I**mpact | People would wear the glasses for this | A curiosity |
| **T**oday | Works on Adventurer with toolkit 1.0.1, no new permissions | Needs hardware or an interface that does not exist |
| **C**ost | Free, on the phone | A model call every few seconds |
| **P**rivacy | Touches only the wearer's own data, on the phone | Records or identifies other people |

**Score** is impact twice, plus the other three, out of 25. Impact counts double because a free, safe, easy feature nobody wants is still not worth building.

"Later" says what a lens display or a Neural Band would add. Where an idea is already shipped by someone else, the row says so.

## The backlog

### Work

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| W1 | **Council** | A yes-or-no question, with a photo if it is about "this", goes to every assistant. Each votes with one reason. Phoenix says the count and reads the dissent. | 5 | 5 | 3 | 4 | 22 | Lens: the tally as a card. Band: a pinch picks whose reason to hear. Model councils exist as command-line tools. Not found on glasses. **Chosen.** |
| W2 | **Relay race** | "Ask Indy to find three caterers, then have Driver book the cheapest." Each assistant gets the one before's answer. | 5 | 5 | 3 | 4 | 22 | Lens: who holds the baton. **Chosen.** |
| W3 | **Close the day** | One sentence gathers what the phone already knows about today (walk-throughs, counts, notes, requests) into a day sheet, and an assistant files it. | 4 | 5 | 4 | 4 | 21 | Lens: the sheet as a list. Health records are left out. **Chosen.** |
| W4 | Roll call | Every assistant says in one line what it is working on. | 3 | 5 | 3 | 5 | 19 | A fixed question to the council. |
| W5 | Assistants can ask you | An assistant sends a yes-or-no question to the glasses. A shake says no. Yes is spoken. | 5 | 3 | 5 | 4 | 22 | Needs a `question` field in the relay. Band: a pinch for yes on Display glasses. |
| W6 | Promise ledger | "I promised Dana the quote by Friday." Read back in the morning, and an assistant can follow up. | 4 | 5 | 5 | 3 | 21 | Shipped elsewhere from recorded conversations (Omi, Fluent, IRIS). Ours would hold only what the wearer says on purpose. |
| W7 | Meeting bookends | "I'm going into the Acme meeting" gets a brief in the ear. "I'm out" takes a dictated debrief and hands out the tasks. | 4 | 5 | 3 | 5 | 21 | Only the wearer's own words. |
| W8 | Check that | Mid-conversation, "Hey Phoenix, check that" sends the wearer's last sentence to Indy and whispers the answer. | 3 | 5 | 3 | 4 | 18 | |
| W9 | Whiteboard to tasks | Smart Capture already keeps the board. An assistant pulls out owners and dates, and another schedules them. | 3 | 5 | 3 | 3 | 17 | A relay race with a photo. |
| W10 | Desk handoff | "Continue this on my computer": the page or screen in view goes to an assistant that opens it there. | 3 | 5 | 3 | 3 | 17 | |
| W11 | Focus session | Head-down time from the motion sensor, with interruptions counted. | 2 | 3 | 5 | 5 | 17 | The motion sensor needs an open session, which takes over two touchpad gestures. |
| W12 | Ear prompter | Cue lines whispered as a talk goes on, following the speaker's words. | 3 | 5 | 5 | 5 | 21 | **Shipped elsewhere** (EarHint, Tellie Nudge, Ear Prompter, and Glass Prompter on the lens). Not building. |
| W13 | **Look to Talk** | Look at an assistant's chat window on the computer and talk to it without its name. The camera finds the name, a badge, or a marker, a tone confirms, and "lock on" holds it when you look away. "The future of a mouse": looking selects, the voice acts. | 5 | 3 | 5 | 4 | 22 | Lens: who is held, always in view. Band: a pinch to lock. Later targets: a document, a browser tab, a shop's order page, sent as context to the held assistant. Asked for by the owner after the ten. **Written, after the ten.** See [After the ten](#after-the-ten-look-to-talk). |

### Business owners

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| B1 | **Walk-through** | Walk a site and talk. "Note", "flag", and "photo" build a punch list with pictures. At the end it is a report, and an assistant files it. | 5 | 5 | 5 | 4 | 24 | Lens: the item count and the last note. A published concept (CantierEye) does this with a model watching every frame. Ours uses no model until the report is sent. **Chosen.** |
| B2 | **Tally** | Count stock by voice: "twelve cases of cups", "minus two lids". Totals are spoken and sent as a sheet. | 4 | 5 | 5 | 5 | 23 | Lens: the running count. Voice picking exists in warehouses on dedicated hardware. **Chosen.** |
| B3 | Checklist with proof | An opening or closing routine where each step needs a photo. The report goes to an assistant. | 4 | 5 | 5 | 4 | 22 | Routines are already built. This adds the photo. |
| B4 | Proof chain | Every kept photo gets a fingerprint, a time, and a place, chained to the one before. An assistant holds the chain off the phone, so a photo can later be shown to be unaltered. | 4 | 5 | 5 | 5 | 23 | C2PA does this inside some cameras. |
| B5 | Shelf scout | A barcode or price tag in view. Indy checks the price elsewhere, Rally checks the budget, and the council says buy or skip. | 4 | 5 | 3 | 5 | 21 | |
| B6 | Quote on site | Dictated measurements and photos. An assistant drafts the estimate and the total is spoken. | 4 | 5 | 3 | 4 | 20 | |
| B7 | Part lookup | Read a model plate. Indy finds the part or the manual. Driver orders it after a spoken yes. | 4 | 5 | 3 | 5 | 21 | |
| B8 | Training by showing | An expert records a routine with a photo for each step. A trainee follows it. | 4 | 3 | 5 | 5 | 21 | The photo needs a lens to be worth it. |
| B9 | Clock in by voice | Job timers with a place. A weekly sheet goes to Rally. | 3 | 5 | 5 | 4 | 20 | |
| B10 | Delivery proof | A photo at the door with place and time, and a message drafted for the customer. | 3 | 5 | 4 | 3 | 18 | |
| B11 | Receipt to books | Smart Capture keeps the receipt. An assistant adds the category and the mileage. | 3 | 5 | 3 | 4 | 18 | |

### Health

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| H1 | **Ingredient watch** | "Check the ingredients." The label is read on the phone and compared with the wearer's own list of allergens. Phoenix reads out the words it matched. It never says "safe". | 5 | 4 | 5 | 4 | 23 | Lens: the matched words as a card. Not found on glasses. Phone apps do it by barcode. **Chosen.** |
| H2 | **Dose guard** | "I'm taking this." The label is read, the dose is logged, and a second dose too soon is called out. "Did I take my ibuprofen?" | 5 | 4 | 5 | 4 | 23 | Shipped on phones and smart speakers (TapMe, Track My Medz, Aasa). Not found on glasses, reading the label. **Chosen.** |
| H3 | Two looks | Read anything that matters from two photos and speak only what both agree on. | 4 | 5 | 5 | 5 | 23 | A building block. Built into H1 and H2. |
| H4 | Meter reader | Read a blood pressure or glucose display and log it. | 3 | 3 | 5 | 4 | 18 | Segment displays are hard for text recognition. Needs two looks and a spoken check. |
| H5 | Appointment companion | With the doctor's agreement, captions are kept, and the instructions become reminders. | 4 | 5 | 5 | 2 | 20 | A medical conversation. Consent every time. |
| H6 | Symptom diary | Dictated entries, and a summary for a doctor. | 3 | 5 | 5 | 3 | 19 | |
| H7 | Meal log by look | A photo of the plate, and a model's estimate. | 3 | 5 | 3 | 4 | 18 | Estimates from a photo are rough. |
| H8 | Eye breaks and water | Timed nudges. | 2 | 5 | 5 | 5 | 19 | |
| H9 | Posture | Time spent head-down, from the motion sensor. | 2 | 3 | 5 | 5 | 17 | Needs an open session. |
| H10 | Drowsy-head watch | A slow droop of the head while driving raises an alarm. | 5 | 2 | 5 | 5 | 22 | Not built. The thresholds need real motion recordings, and a watch that misses is worse than none. |

### Accessibility

The accessibility suite and its own list of ideas are in [ACCESSIBILITY.md](ACCESSIBILITY.md). These are additions.

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | Finder tone | For "find the door", a beep that speeds up as the target centers. | 4 | 5 | 5 | 5 | 23 | Already first on the accessibility list. |
| A2 | Framing coach | Before reading: "move it left", "hold it further away". | 4 | 5 | 5 | 5 | 23 | Already on the accessibility list. Would help H1 and H2. |
| A3 | Supporter link | A question and a photo go, through an assistant, to a person the wearer trusts. Their typed answer is spoken. | 4 | 4 | 4 | 3 | 19 | Depends on what the assistant can deliver. |
| A4 | Mail sorter | Read the sender on an envelope. Bills go to Rally. | 3 | 5 | 4 | 3 | 18 | |
| A5 | Clothing matcher | Colors and patterns remembered: "does this go with the gray jacket?" | 3 | 5 | 5 | 5 | 21 | |
| A6 | Line helper | "Tell me when the line moves." | 3 | 5 | 5 | 3 | 19 | The camera stays on people. |
| A7 | Nod for next | "Next" and "repeat" by head movement in a routine or a reading. | 3 | 4 | 5 | 5 | 20 | The head moves for many reasons. Needs testing on glasses. |
| A8 | Appliance panel | Learn a flat control panel once, then say where "start" is. | 3 | 3 | 4 | 5 | 18 | |
| A9 | Captions with direction | Captions on the lens with an arrow toward the speaker. | 4 | 1 | 5 | 3 | 17 | Needs a lens, and the toolkit does not say where a sound came from. |

### Learning

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| L1 | Walk quiz | Flashcards asked aloud on a walk, spaced over days. A nod means "knew it", a shake means "missed it". | 4 | 5 | 5 | 5 | 23 | **Shipped elsewhere** for the voice part (Loudwalk, Encodr, Cognicard, and SmartGlasses.study on Meta glasses). The nod and cards made from a look would be new. |
| L2 | Word catcher | Abroad: "what's this called?" The word becomes a card, and is asked again when the same thing is in view. | 4 | 4 | 4 | 5 | 21 | |
| L3 | Lab notebook | Narrated steps with photos become a dated notebook that an assistant writes up. | 4 | 5 | 4 | 5 | 22 | The walk-through engine with another template. |
| L4 | Lecture bookmarks | A press of the capture button marks "explain this later". Afterwards Indy explains each one. | 4 | 3 | 3 | 3 | 17 | The button works only while Phoenix is busy. Slides belong to the lecturer. |
| L5 | Museum companion | A placard is read, and Indy tells the story at the depth asked for. | 3 | 5 | 3 | 5 | 19 | |
| L6 | Rehearsal coach | Pace and long pauses in a practice talk. | 3 | 5 | 5 | 5 | 21 | Shipped on phones. Speech recognizers drop "um", so filler counts would be wrong. |
| L7 | Read-along | A child reads aloud and the glasses follow the page. | 3 | 3 | 5 | 3 | 17 | |
| L8 | Field guide | Birdsong or a plant, named. | 3 | 3 | 4 | 5 | 18 | Planta already identifies plants on these glasses. |

### Travel

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T1 | **Place notes** | "Leave a note here: breaker fourteen is the kitchen." Back at that spot, "any notes here?" reads it, and putting the glasses on there offers it. | 4 | 5 | 5 | 4 | 22 | Lens: a card on arrival. **Chosen.** |
| T2 | Trail breadcrumbs | "Mark this spot." Later, "take me back" guides to it with the walking cues. | 4 | 5 | 5 | 5 | 23 | Walking guidance is already built. |
| T3 | Menu check | A menu in another language is translated on the phone and checked against the allergen list. | 4 | 3 | 5 | 4 | 20 | The allergen words are English today. |
| T4 | Split the bill | The total is read from the receipt. "Four ways with twenty percent." | 3 | 5 | 5 | 5 | 21 | Shipped on phones. |
| T5 | Trip ledger | Spending by voice in any currency. An assistant converts it each night. | 3 | 5 | 4 | 4 | 19 | |
| T6 | Gate watch | Driver watches the flight and pushes changes to the glasses. | 3 | 5 | 3 | 5 | 19 | Mostly the assistant's work. |
| T7 | Phrase coach | "How do I say…", then it listens to the attempt. | 3 | 5 | 4 | 5 | 20 | |
| T8 | Departure board | "When is the next train to Lyon?" read from the board. | 3 | 3 | 5 | 5 | 19 | |
| T9 | Travel journal | The day's kept photos, place notes, and spoken lines, written up by an assistant. | 3 | 5 | 3 | 4 | 18 | Close the day with another template. |

### Creators

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C1 | Voice slate | "Scene three, take two." Clips are named as they are recorded, "good take" marks one, and the log goes to the editor. | 4 | 5 | 5 | 5 | 23 | |
| C2 | Shot list walker | A shot list read one shot at a time, each recorded and ticked off. | 4 | 5 | 4 | 5 | 22 | |
| C3 | Tutorial builder | Narrated steps and photos, and an assistant drafts the post. | 4 | 5 | 3 | 5 | 21 | The walk-through engine. |
| C4 | Time-lapse | A still every few seconds, joined into a video. | 3 | 4 | 5 | 4 | 19 | Simply Draw does this for drawing. The light stays on and the glasses warm up. |
| C5 | Title room | After a shoot the council proposes titles, and a shake rejects each one. | 3 | 5 | 3 | 5 | 19 | |
| C6 | Continuity check | A photo of the set before a break. Afterwards, what changed. | 3 | 4 | 4 | 5 | 19 | |
| C7 | Sound scout | Loudness and the kind of noise at a spot, from the glasses' microphones. | 2 | 4 | 5 | 5 | 18 | |
| C8 | Live stream | Frames from the glasses sent on to a streaming service. | 3 | 2 | 2 | 3 | 13 | Heat, battery, and no support in the toolkit. |

### Home

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| O1 | Home inventory | A walk-through of each room with spoken values, kept for insurance. | 4 | 5 | 5 | 4 | 22 | Built as a walk-through. |
| O2 | Pantry count | A tally of the pantry, and "we're out of this" adds what is in view to the shopping list. | 4 | 5 | 5 | 5 | 23 | The count is built as a tally. |
| O3 | Cook-along | A recipe as a routine with a timer for each step. | 4 | 5 | 5 | 5 | 23 | Routines and timers are built. Joining them is not. |
| O4 | Fix-it helper | A model plate, the manual, and the steps one at a time. | 4 | 5 | 3 | 5 | 21 | Part lookup, then a routine. |
| O5 | Utility meter | Read the meter each month and send the number. | 3 | 4 | 5 | 5 | 20 | Needs two looks. |
| O6 | House notes | Place notes for a sitter or a guest. | 2 | 5 | 5 | 4 | 18 | |
| O7 | Plant and pet log | A look and a sentence. | 2 | 5 | 5 | 5 | 19 | |

### Safety

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| S1 | Lost glasses | Where and when the glasses were last taken off or last connected. | 4 | 5 | 5 | 5 | 23 | Check first whether the Meta AI app already answers this. |
| S2 | Lone-worker check | A spoken check at intervals. No answer, and an assistant tells a supervisor. | 4 | 4 | 4 | 4 | 20 | Depends on what the assistant can deliver. |
| S3 | Incident log | One phrase starts stills, place, and time, each sent off the phone as it is taken, with the light on and a spoken "recording". | 4 | 5 | 3 | 2 | 18 | Records other people. The law differs by place. |
| S4 | Scam shield | A letter or message is read, and fixed rules flag urgency and gift cards. The council gives a second opinion. | 3 | 5 | 4 | 5 | 20 | |
| S5 | Check-in timer | "Walk me home": no check-in by the deadline alerts a contact. | 3 | 4 | 5 | 4 | 19 | **Shipped by Apple** as Check In. |
| S6 | Hazard report | A photo and a place, sent to the landlord or the city by an assistant. | 2 | 5 | 3 | 4 | 16 | |

### Social

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | People file | Notes the wearer chooses to keep about someone. "Brief me on Dana." | 4 | 5 | 5 | 2 | 20 | Shipped elsewhere from recordings (Omi, IRIS, Fluent). Notes about other people are a risk even on the phone. |
| P2 | Two-wearer link | Two wearers share a relay room. "Tell Alex I'm at the north gate" is spoken in Alex's glasses. | 4 | 3 | 4 | 3 | 18 | Needs relay rooms between owners. |
| P3 | Shared look | "Show this to Sam." | 3 | 4 | 5 | 4 | 19 | Built as far as iOS allows: the wearer still taps send. |
| P4 | Event brief | Before an event, an assistant briefs from the wearer's own calendar and notes. | 3 | 5 | 3 | 3 | 17 | |
| P5 | Group photo timer | "Take it in five", with a countdown chime. | 2 | 5 | 5 | 5 | 19 | |
| P6 | Walk stories | A child's finds on a walk become a bedtime story. | 3 | 5 | 3 | 3 | 17 | |
| P7 | Thank-you ledger | Who helped, and a reminder to thank them. | 2 | 5 | 5 | 3 | 17 | |

### Developer platform

| # | Idea | What it does | I | T | C | P | Score | Later, and notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D1 | **Skills** | A short file adds a spoken command: the phrases, what to capture (a photo, the text in view, the place), and which assistant gets it. No code and no addresses. The wearer sees what it takes before adding it. | 5 | 4 | 3 | 3 | 20 | Lens: a skill can name a card. Band: a gesture can start one. Other glasses assistants add tools through MCP servers, which is code. **Chosen**, by judgment: it multiplies everything else. |
| D2 | **Standing orders** | "Whenever I put the glasses on, ask Fire Fox for my brief." Triggers: put on, taken off, battery low, a time of day. | 5 | 5 | 3 | 4 | 22 | Band: a gesture as a trigger. Not found elsewhere. **Chosen.** |
| D3 | What left my phone | "What left my phone today?" Every request that went out, to whom, and whether a photo went with it. | 5 | 3 | 5 | 5 | 23 | Only honest if it is complete: cloud voices, the speech service, and telemetry too. It has to be counted at one place all traffic passes, or not shipped. |
| D4 | Capture requests | An assistant asks for a look. The wearer says yes, the light comes on, and one photo goes. | 4 | 3 | 4 | 3 | 18 | Needs a relay field. |
| D5 | Events to assistants | Put on, taken off, walk-through finished: sent to the assistants the wearer chooses. | 4 | 4 | 5 | 3 | 20 | |
| D6 | Glasses as tools | The assistants see "speak", "ask yes or no", and "request a look" as tools through the relay. | 4 | 3 | 4 | 3 | 18 | |
| D7 | Shortcuts for everything | Every command as an iOS shortcut action. | 3 | 5 | 5 | 5 | 21 | |
| D8 | Skill packs | Bundles of skills, signed, with review. | 3 | 3 | 5 | 3 | 17 | After there are skills worth bundling. |
| D9 | Any brain | A skill's assistant can be Grok, ChatGPT, Gemini, or Claude. | 3 | 4 | 3 | 4 | 17 | |
| D10 | Lens kit | A skill's reply as a card, with band gestures named in the file. | 4 | 1 | 5 | 5 | 19 | Display glasses only. |

## The ten

The rule: the highest scores, with two conditions. At least four of the ten must need the team of assistants, because that is what this app has and others do not. And one must be the platform, because it lets other people add the next hundred.

Ideas that scored as high but are already shipped by someone else, or are a template of a chosen one, are in [The next ten](#the-next-ten).

| | Idea | Why it is in |
| --- | --- | --- |
| 1 | **Walk-through** (B1) | The highest score. A business owner's hands are full on a site, and the report is the tedious part. Home inventory, a lab notebook, and a tutorial are the same engine. |
| 2 | **Tally** (B2) | Counting by voice with both hands on the stock. Free, private, and the pantry count is the same engine. |
| 3 | **Ingredient watch** (H1) | Glasses read a label held in one hand in a shop aisle. The phone does all of it. |
| 4 | **Dose guard** (H2) | "Did I take it?" is asked by nearly everyone on a daily medicine. Reading the label is what the glasses add. |
| 5 | **Council** (W1) | The clearest use of four assistants at once: a decision with the disagreement spoken, not averaged away. |
| 6 | **Relay race** (W2) | Delegating a chain of work in one sentence. |
| 7 | **Standing orders** (D2) | The glasses know when they are put on. Nothing else in the day is as reliable a signal that the wearer is starting. |
| 8 | **Place notes** (T1) | A note where it will be needed, heard when the glasses go on there. |
| 9 | **Close the day** (W3) | It is what makes the other nine add up: the day's work is handed to the team in one sentence. |
| 10 | **Skills** (D1) | The platform. Scored lower on cost and privacy because a skill can ask for a photo, which is why every skill shows what it takes before it is added. |

### Status

All ten are in the owner build only, under **Settings → Owner build → Workshop**, each with its own switch. A standard build ignores them.

| Idea | Status | What is not done |
| --- | --- | --- |
| Walk-through | Written | Not run on glasses. At most 12 photos go to the assistant with a report, flags first, and they share the relay's size limit, so more photos means smaller pictures. The rest stay on the phone. No PDF: the report is text. |
| Tally | Written | Not run on glasses. Numbers above 9,999 and fractions are not understood. |
| Ingredient watch | Written | Not run on glasses. English labels only. Whether the whole-sensor photo reads small print in a shop aisle is unknown. |
| Dose guard | Written | Not run on glasses. No schedule or reminders: it logs and warns. It does not check one medicine against another. |
| Council | Written | Not run against the live relay. Each assistant is asked separately, so the wait is as long as the slowest one, up to the relay's time limit. |
| Relay race | Written | Not run against the live relay. Four steps at most. |
| Standing orders | Written | Not run on glasses. Orders fire only while the app is running. |
| Place notes | Written | Not run on glasses. The offer when the glasses are put on needs location allowed. |
| Close the day | Written | Not run against the live relay. |
| Skills | Written | Not run against the live relay. Skills are added by pasting the file and shared as text. No signing, catalogue, or lens cards. See [SKILLS.md](SKILLS.md). |

"Written" means what it means in [FEATURE_PARITY.md](FEATURE_PARITY.md): the decisions are covered by unit tests that run on Linux, the code that joins them to the phone was type-checked against stand-ins, and no Xcode build or pair of glasses has seen it.

### After the ten: Look to Talk

Look to Talk (W13) was asked for by the owner after the ten were chosen. It scores 22, with a 3 for "today": everything it needs exists on the Adventurer, but whether the camera can read a window's title from a desk is not known, so a badge or a marker may be needed.

| Idea | Status | What is not done |
| --- | --- | --- |
| Look to Talk | Written | Never built by Xcode or run on glasses. Off by default, with its own switch under **Settings → Owner build → Workshop → Look to Talk**, and the owner profile does not turn it on. It is on its own branch, to be merged after the first release is stable. Reads text and QR codes only: avatars are not recognized. The lens gets the spoken lines as cards and no lasting mark of who is held. Other kinds of target (a document, a tab, an order page) are designed for and not built. Every threshold is untuned. See [LOOK_TO_TALK.md](LOOK_TO_TALK.md). |

## The next ten

In order.

1. **Proof chain** (B4). It would make a walk-through report evidence.
2. **Assistants can ask you** (W5). Needs one field in the relay.
3. **Trail breadcrumbs** (T2). Small, because walking guidance exists.
4. **Voice slate** (C1).
5. **Checklist with proof** (B3).
6. **What left my phone** (D3), once it can be complete.
7. **Lost glasses** (S1), after checking what Meta AI already does.
8. **Cook-along** (O3).
9. **Walk quiz with a nod** (L1). The voice part is shipped elsewhere. The nod is not.
10. **Finder tone and framing coach** (A1, A2), from the accessibility list.

## What we said no to

- **Listening to the room all day.** Several products turn every conversation into notes and tasks. It works, and it records people who did not agree. Phoenix Fox keeps only what the wearer says to it on purpose.
- **Recognizing strangers.** Faces are matched only against people who agreed to be saved.
- **The camera without the light.** There is no such mode, and no idea here needs one.
- **A drowsiness alarm we cannot test.** High impact and not built, because nobody here can record the head motion needed to set it, and a safety alarm that misses is worse than none.
- **A privacy ledger that might be incomplete.** "What left my phone" is the right feature and it is on the next list, not the built one, for the reason in its row.
- **An ear prompter and a plain flashcard app.** Good ideas that other people have already built well.
- **Code in plugins.** A skill that can run code or name a server can send a photo anywhere. Skills are a file, and the only place they can send anything is the wearer's own assistants.

## Who else is building

Found in a brief search on 14 November 2026. Each is worth a longer look before any public claim that Phoenix Fox does something first.

| Who | What | What it means here |
| --- | --- | --- |
| OpenGlasses, now Avenkin | An open-source assistant for Meta glasses with many built-in tools, several models, personas with their own wake words, MCP tool servers, and field-service guidance | The closest thing to Phoenix Fox. It routes between models. It does not, as far as its pages say, run a team of assistants that vote or hand work on. |
| Aira, OOrion | Accessibility on Meta's toolkit: live human interpreters, and object and text finding | Compared in [ACCESSIBILITY.md](ACCESSIBILITY.md) |
| Planta, Simply Draw | Plant care and drawing lessons on Meta's toolkit | Single-purpose apps. Skills are how Phoenix Fox would host the same kind of thing. |
| IRIS on Even Realities G2 | Briefings before a conversation and written-up promises after it, on a lens | The people file and promise ledger, done from recordings |
| Omi, Fluent | A pendant and an app that turn recorded conversations into tasks and per-person notes | Same |
| EarHint, Tellie Nudge, Ear Prompter, Glass Prompter | Prompters in the ear and on the lens that follow the speaker | Why the ear prompter is not built |
| Loudwalk, Encodr, Cognicard, SmartGlasses.study | Flashcards asked and answered aloud | Why the walk quiz is not in the ten |
| TapMe, Track My Medz, Aasa | Medication logs with a double-dose warning, by tap, by smart speaker, and by phone camera | Dose guard is not new as an idea. Reading the label through glasses was not found. |
| Roundtable and similar | Several models answer one question and vote, from a command line | Council is not new as an idea. Asked aloud about what the wearer is looking at was not found. |
| Meta, in patent application WO2023091403A2 | Glasses with eye tracking that work out which of several assistants on their display the wearer is speaking to, from the direction of their gaze | Look to Talk is not new as an idea. Ours reads a separate computer's screen through the outward camera and follows the head, not the eyes. Whether the application matters is a question for a lawyer before any public claim. See [LOOK_TO_TALK.md](LOOK_TO_TALK.md#who-else). |
