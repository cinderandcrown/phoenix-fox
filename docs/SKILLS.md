# Skills

A skill teaches Phoenix Fox one new spoken command. It is a small JSON file that says three things: which phrases start it, what the glasses capture, and what to ask one of the wearer's assistants. It contains no code.

Skills are one of the ten features in the [innovation backlog](INNOVATION_BACKLOG.md). They are in the owner build only, under **Settings → Owner build → Workshop → Skills**. Nothing here has been run on glasses yet. The status is in the backlog's status table.

Skills must feel like presence, not a macro dump: short spoken confirmation, capture only what was declared, reuse conversation context when the wearer follows up, and never start themselves. See the [presence checklist](DESIGN_PRINCIPLES.md#presence-checklist-every-feature).

## What a skill can and cannot do

A skill can:

- start when the wearer says one of its phrases
- take one photo through the glasses and send it to the assistant
- read the words in view on the phone and send the words (the picture is not sent)
- send where the wearer is, to about ten meters
- send the date and time
- send what the wearer said after the phrase
- have the answer spoken, or say only "Sent" and put the answer in the task log

A skill cannot:

- run code on the phone
- name a server or a web address: the only place a skill sends anything is the wearer's own relay, to the wearer's own assistant
- capture anything it did not declare: a photo is taken only when `capture` lists `photo` or `text`, and the glasses' capture light is on when it is
- start by itself: it runs only when the wearer says its phrase
- replace a built-in command: built-in commands are matched first
- read the wearer's memories, notes, place notes, or medicine log

Like every request to an assistant, a skill's request carries the last few turns of the conversation, so the assistant can follow what "it" means. Turns about medicine and ingredients are never among them.

Before a skill is added, the app shows every phrase, everything it captures, and the full text it will send. The wearer adds it, or does not.

**Read the ask before you add a skill from someone else.** The ask is sent to your assistant as if you had said it. Your assistant can do whatever you have let it do, so a skill whose ask says "send my calendar to…" is asking your assistant to do exactly that. The app refuses an ask that contains a web address, but it cannot judge what a sentence means. The same goes for `capture: ["text"]`: the words on a sign or a page are sent to your assistant, and they were written by whoever wrote the sign.

## The file

```json
{
  "format": 1,
  "id": "price-check",
  "name": "Price check",
  "about": "Look at a product or a price tag and hear whether the price is a good one.",
  "phrases": ["price check", "is this a good price"],
  "capture": ["photo"],
  "bot": "Indy",
  "ask": "Find the product in the photo. In two sentences, say what it usually sells for and whether the price shown is a good one.",
  "speak": "reply"
}
```

| Field | Required | Rules |
| --- | --- | --- |
| `format` | No | The version of this format. Only `1` exists. A file with a higher number is refused. Left out, it is 1. |
| `id` | Yes | 3 to 40 lowercase letters, digits, and hyphens. No hyphen first or last. Adding a skill with the id of one already added replaces it, and the app says so first. |
| `name` | Yes | 1 to 40 characters. |
| `about` | No | One or two sentences for the list. Cut at 200 characters. |
| `phrases` | Yes | 1 to 8 phrases. See [Phrases](#phrases). |
| `capture` | No | Any of `"photo"`, `"text"`, `"place"`, `"time"`. Left out, nothing is captured. |
| `bot` | No | The assistant to ask, by the name the wearer gave it. Left out, the wearer's main assistant is asked. If the wearer has no assistant by that name, the skill says so and does nothing. |
| `ask` | Yes | What is sent to the assistant. 1 to 1,000 characters. See [The ask](#the-ask). |
| `speak` | No | `"reply"` speaks the answer. `"quiet"` says "Sent" and puts the answer in the task log. Left out, it is `"reply"`. |

A field that is not in this table is refused, not ignored. A file that asks for something this version cannot do must not look as if it was accepted.

No field may contain a web address, an internet address in numbers, or anything starting with `http:`, `https:`, `www.`, or `mailto:`.

### Phrases

- A phrase needs at least two words and six letters before any slot. "Price check" is a phrase. "Check" is not.
- Capitals and punctuation do not matter. The wake word, "please", and "can you" in front are ignored.
- A phrase may end with one slot in braces: `"log an expense {what}"`. The slot takes everything said after the phrase, in the wearer's own words. A slot name is plain letters. A slot can only come last.
- A phrase without a slot matches only when it is the whole sentence. A phrase with a slot matches when the sentence starts with it and something follows.
- A phrase cannot start with a word kept for commands that must always work: stop, cancel, quiet, call, text, message, emergency, help, yes, no, phoenix, hey, undo.
- A phrase cannot be one that another added skill already uses.
- When two phrases match, the longer one wins. A built-in command always wins over a skill.

### The ask

The ask is plain text with placeholders in braces:

| Placeholder | Filled with | Needs |
| --- | --- | --- |
| `{text}` | The words in view, read on the phone, up to 3,000 characters. "(no words could be read)" when there were none. | `"text"` in `capture` |
| `{place}` | Latitude and longitude to four decimal places. "(the place is not known)" when the phone cannot tell or location is not allowed. | `"place"` in `capture` |
| `{time}` | The date and time on the phone. | `"time"` in `capture` |
| `{anything else}` | What the wearer said after the phrase. | Every phrase must end with that same slot. |

A placeholder that is neither captured nor a slot is refused. A photo has no placeholder: it is attached to the request.

If a phrase's slot has one of the names above, the slot wins: `"note the time {time}"` sends what the wearer said, not the clock.

## What the wearer hears

| The skill | The wearer hears |
| --- | --- |
| Runs, `speak` is `reply` | The assistant's answer |
| Runs, `speak` is `quiet` | "Sent." |
| Needs a photo and the glasses give none | "I couldn't get a picture, so I did not run" and the skill's name |
| Names an assistant the wearer does not have | That, and where to change it |
| The relay cannot be reached | The same line any other request gets |

Saying "list my skills" reads each skill's name and its first phrase.

## Examples

Five skills come with the app. None is added until the wearer adds it. Each can be shared as a file from its screen, which is the easiest way to start one of your own.

| Skill | Say | Captures | Asks |
| --- | --- | --- | --- |
| Price check | "price check" | A photo | Indy |
| Log an expense | "log an expense" and what was spent | Place and time | Rally |
| Plant doctor | "plant doctor" | A photo | The main assistant |
| Standup note | "standup note" and the note | Nothing | Fire Fox, quietly |
| Explain this notice | "explain this notice" | The words in view | The main assistant |

The three that name an assistant use the owner's names. Change `bot` to one of yours, or leave it out.

A skill with a slot, the place, and the time:

```json
{
  "id": "expense",
  "name": "Log an expense",
  "about": "Say what you spent. The time and place go with it.",
  "phrases": ["log an expense {what}", "expense this {what}"],
  "capture": ["place", "time"],
  "bot": "Rally",
  "ask": "Record this expense: {what}. Time: {time}. Place: {place}. Reply with the one line you recorded."
}
```

A skill that reads on the phone and sends only the words:

```json
{
  "id": "sign-explainer",
  "name": "Explain this notice",
  "phrases": ["explain this notice", "what does this notice mean"],
  "capture": ["text"],
  "ask": "This is the text of a notice I am looking at. Explain in plain words what it asks me to do, in three sentences at most.\n\n{text}"
}
```

## Adding one

1. In the app, open **Settings → Owner build → Workshop → Skills**.
2. Choose **Add a skill from its file** and paste the file's text.
3. Choose **Check it**. The app shows what is wrong with the file, or what the skill captures and asks.
4. Read the ask. Choose **Add**.

Up to 30 skills can be added. Swipe one to remove it.

## What the assistant receives

A skill's request arrives at the relay like any other request, with the `intent` field set to `skill:` and the skill's id, for example `skill:price-check`. A bot can use that to treat a skill's request differently from a spoken one. The relay contract is in [RELAY_API.md](RELAY_API.md).

## What is not here yet

- No signing and no catalogue. A skill is trusted because the wearer read it.
- No way to add a skill from a link or a file on the phone. It is pasted.
- No cards on a lens. Replies are spoken, and shown as a plain reply card on glasses with a display.
- One request, one answer. A skill cannot ask a follow-up question or chain assistants. [Relay race](INNOVATION_BACKLOG.md#the-ten) does chains, by voice.
- English phrases only.
