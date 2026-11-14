# Meta AI Connector plan

**Status:** design only — developer preview; no connector shipped from this repo yet.  
**Source:** [Meta Wearables FAQ — Meta AI Connectors](https://developers.meta.com/wearables/faq/), Wearables Developer Center.

## What a Connector is

Meta AI Connectors turn **your API into tools Meta AI can call** inside the Meta AI conversation. The wearer stays in “Hey Meta”; Meta AI invokes your actions when they fit. There is no new mobile SDK and no second app to open.

For Phoenix Fox the goal is: someone says **Hey Meta**, and can reach the same Grok / Fire Fox / Indy / Driver / Rally bots (and later other brains) that the phone already routes through the **relay**.

## Why it sits beside DAT and Web Apps

| Path | Who runs it | When to use |
| --- | --- | --- |
| DAT mobile companion | Phoenix Fox iOS | Full glasses camera/mic/motion, Jarvis wake on phone |
| Display Web App | On-lens HTML/JS | Glanceable cards + Neural Band on Ray-Ban Display |
| **Meta AI Connector** | Meta AI runtime → our HTTPS tools | Stay inside Meta AI; no app switch |

Connectors do not replace DAT. They cover the “I already talking to Meta AI” moment.

## Proposed tools (draft)

Names are illustrative until Meta’s connector schema is locked in the preview docs.

| Tool | Purpose | Backing |
| --- | --- | --- |
| `phoenix.status` | Battery, worn, last bot, open asks | Relay `GET /health` + phone push state if available |
| `phoenix.ask` | Send a short ask to a named bot or `all` | Relay `POST /ask` + wait/poll reply |
| `phoenix.inbox.walk` | Start / act / skip walk-my-inbox | Same semantics as head yes/skip |
| `phoenix.resume` | Pick up where I left off | Session resume snapshot |
| `phoenix.feedback` | File a beta report | Relay `POST /feedback` |

Auth: wearer’s relay bearer must **never** be embedded in Meta’s tool definitions as a long-lived secret in the clear. Prefer:

1. User links Phoenix Fox once in Meta’s connector consent UI.
2. We issue a scoped connector token (rotate, revoke) that maps to their relay.
3. Tool calls hit `https://<our-connector-gateway>/…`, which calls the owner’s relay.

## Mapping to existing product

- **Grok Bot routines / webhooks:** already receive asks via `BOT_WEBHOOKS` (optional custom headers). A Connector `phoenix.ask` should produce the same mailbox shape so bots do not care whether the ask came from the phone or Meta AI.
- **Voice Invocations (DAT):** “Hey Meta” → launch Phoenix Fox stays the DAT path. Connector is for *staying* in Meta AI without launching us.
- **WebMCP:** complementary on Display Web Apps; Connector is Meta-AI-global, WebMCP is per Web App.

## Acceptance / compliance

Before any public connector:

1. Meta Wearables Developer **Acceptable Use Policy** (see App Store readiness in [BETA_TESTING.md](BETA_TESTING.md)).
2. No silent camera or mic from a connector tool — camera remains explicit DAT sessions with the capture light.
3. Clear disclosure that answers may come from the wearer’s chosen bots / models, not from Meta.
4. Rate limits aligned with relay limits; no bulk scraping tools.

## Build order (when preview access lands)

1. Read the live Connector preview docs in Wearables Developer Center; adjust tool schemas.
2. Implement a minimal gateway (ask + status only) in front of the existing relay.
3. Owner-only test channel → 5–10 testers → wider.
4. Do **not** block Adventurer audio/camera v1 on Connector availability.

## Explicit non-goals for now

- No connector gateway code in this PR.
- No Meta AI OAuth client id committed to the app binary.
- No claim that “Hey Meta” already routes to Grok bots until the connector is live and verified.
