# Display Web App plan (Meta Ray-Ban Display)

**Status:** design only — no Web App build in this repo yet.  
**Source:** [Meta Wearables FAQ](https://developers.meta.com/wearables/faq/), [Web Apps docs](https://wearables.developer.meta.com/docs/develop/), and Meta’s [meta-wearables-webapp](https://github.com/meta/meta-wearables-webapp) Cursor skills (installed locally for agents).

## Why this exists

Phoenix Fox today reaches the wearer through:

1. **Spoken audio** on every pair (Adventurer and other displayless glasses).
2. **DAT `MWDATDisplay` cards** on Meta Ray-Ban Display, via `GlassesHUD` / `CompanionSurface`.

Meta’s FAQ adds a third path for Display glasses only: **Web Apps** — HTML/CSS/JS running on the glasses, Neural Band input, optional **WebMCP** so “Hey Meta” can drive in-app actions. No native SDK required for that surface.

One product should not fork three UIs. Cards must be **display-agnostic**.

## Portable card schema

The app already owns a portable type: `CompanionCard` (`OpenVision/Services/Glasses/CompanionCard.swift`).

| Field | Role |
| --- | --- |
| `id` | Stable id for act/skip/dismiss |
| `kind` | `reply`, `alert`, `briefing`, `caption`, `resume`, `inboxItem` |
| `bot` | Speaker / owner of the line |
| `text` | Primary line (spoken + shown) |
| `bullets` | Secondary lines |
| `actions` | Hints: `act`, `skip`, `next`, `dismiss`, `talk` |

`CompanionSurface` always speaks, then optionally draws via DAT Display. A future Web App consumes the **same JSON** over a small bridge (relay, local HTTPS, or WebMCP tool results).

Do **not** put FlexBox / SwiftUI / DOM nodes in feature code. Map `CompanionCard` → renderer at the edge:

| Surface | Renderer |
| --- | --- |
| Audio only | TTS only |
| DAT Display | `GlassesHUD` ← `CompanionCard.asHudCard()` |
| Web App | React + `@wearables-ui-toolkit/mrbd` (Meta UI Toolkit) |

## Input model on Display (Web App)

From Meta’s Web App skills (Neural Band / captouch):

- D-pad navigates focusable elements.
- Pinch activates the focused control (not a free cursor).
- Continuous drag is opt-in (`touch-action: none`).
- Back = thumb + middle-finger (or Escape) — no on-screen back button.
- Text fields open the on-glasses handwriting / voice composer.

Map Phoenix Fox actions:

| Companion action | Web App binding |
| --- | --- |
| `next` / `skip` | D-pad down or shake (IMU) / Skip button |
| `act` | Pinch on focused item / nod |
| `dismiss` | Back gesture |
| `talk` | Pinch on “Talk to Jarvis” |

Head nod/shake from DAT Motion on the **phone** companion remains valid while the Web App is open; the Web App may also read W3C sensors on-device. Prefer one authority per session to avoid double-firing.

## WebMCP (developer preview)

WebMCP lets the Web App declare tools on `document.modelContext` so Meta AI can call them hands-free. Plan (not built):

- `phoenix.presentCard` — push a `CompanionCard`
- `phoenix.inbox.act` / `phoenix.inbox.skip`
- `phoenix.resume` — pick up where I left off
- `phoenix.ask` — forward a short ask to the wearer’s relay bots (Grok / Fire Fox / …)

Keep the allow-list tight; never expose raw relay tokens to the glasses JS context — the phone or a backend mint short-lived session credentials.

## Build order (when we start)

1. Freeze `CompanionCard` JSON schema in this doc + a golden fixture test (already covered lightly in `CompanionCardTests`).
2. Scaffold a separate `webapp/` package with Meta’s `create-webapp` skill (React + Vite + UI Toolkit). **Out of tree or later PR — not this one.**
3. Bridge: phone posts cards to the Web App; Web App posts actions back.
4. Simulator first (Meta browser simulator); then on-device Developer Mode URL / QR.
5. Submit to Meta discovery only after AUP review (see [BETA_TESTING.md](BETA_TESTING.md) and [APP_STORE_PLAN.md](APP_STORE_PLAN.md)).

## Explicit non-goals for now

- No Web App binary or `webapp/` tree in this PR.
- No dependency on Display hardware for Adventurer v1.
- No assumption that Mock Device Kit covers Display Web Apps (FAQ: Mock Device Kit does not support display glasses the same way).
