# Beta testing

Owner priority for readiness: structured feedback (shake / “Jarvis, report a bug” / TestFlight screenshots), then phased testers, then App Store / Meta discovery when those doors open.

## Phased plan

| Phase | Who | Goal |
| --- | --- | --- |
| **0 — Owner only** | Adventurer + owner TestFlight (`PHOENIX_FOX_OWNER_BUILD=YES`) | Glasses registration, HFP audio, one look photo, head yes/skip, relay bots. File feedback via shake / voice / TestFlight screenshot. |
| **1 — Closed** | 5–10 trusted testers, **including at least two accessibility users** (VoiceOver / hearing / motor as available) | Same core path on displayless glasses; Accessibility suite smoke; no experimental motion required for pass. Collect `/feedback` reports for 30 days on the relay. |
| **2 — Wider TestFlight** | Larger external group | Stability, onboarding, privacy copy, battery. Still Wearables release-channel + TestFlight — not public App Store until Meta/Apple allow it. |

Do not skip Phase 1 accessibility coverage: the free accessibility suite is a ship gate for “life-changing,” not a polish pass.

## Per-build test checklist (template)

Copy for each TestFlight build. Mark Pass / Fail / N/A.

**Build:** ________  **Date:** ________  **Tester:** ________  **Glasses:** ________

### Core
- [ ] Install from TestFlight; first launch onboarding completes
- [ ] Pair / register through Meta AI app; Phoenix Fox shows connected
- [ ] “Jarvis …” wake; reply heard on glasses speakers
- [ ] “Take a picture” / look: capture light on only while camera runs
- [ ] Relay ask to Fire Fox (or configured bot) returns a spoken reply
- [ ] Taking glasses off ends the controls session; putting them on restores input

### Presence / motion (owner build)
- [ ] Nod = yes / shake = no on an accessibility confirmation that allows head yes
- [ ] Walk-my-inbox (when enabled): nod acts, shake skips
- [ ] Doff mid-task → don + look level offers resume (when feature enabled)

### Feedback
- [ ] Shake opens report sheet; submit reaches relay (`POST /feedback`)
- [ ] “Jarvis, report a bug …” same path; note + redacted diagnostics only
- [ ] TestFlight screenshot sheet still available; used for annotated screenshots
- [ ] `/health` and feedback logs show **no** tokens, keys, or raw media

### Accessibility smoke (Phase 1+)
- [ ] VoiceOver: Settings and main talk screen navigable
- [ ] “Read this” / Guide mode safety notice (if exercised)
- [ ] Captions or sound alerts toggle does not crash

### Failures to file
- Repro steps, build number, glasses model/firmware, audio route, provider/error code.

## Triage labels

Use on GitHub issues / feedback notes:

| Label | Meaning |
| --- | --- |
| `beta/blocker` | Stops Phase advance or TestFlight trust |
| `beta/glasses` | DAT registration, stream, light, motion, inputs |
| `beta/audio` | HFP / A2DP / route / mic |
| `beta/relay` | Ask / reply / webhook / feedback store |
| `beta/a11y` | Accessibility suite |
| `beta/privacy` | Redaction miss, unexpected upload, consent |
| `beta/meta-aup` | Acceptable Use / discovery / connector policy |
| `beta/wontfix-v1` | Parked until Display / Connector / Store |

## Feedback channels

1. **In-app** → relay `POST /feedback` (30-day retention; bots `GET /feedback`). See [RELAY_API.md](RELAY_API.md).
2. **TestFlight** screenshot feedback (Apple) — screenshots and annotations.
3. Do not ask testers to paste API keys into tickets.

## App Store readiness checklist

Still gated by Meta MFi / publishing policy ([APP_STORE_PLAN.md](APP_STORE_PLAN.md)). Track anyway:

### Security review
- [ ] No secrets in repo or TestFlight logs
- [ ] Relay bearer only in Keychain; connector tokens rotatable (when Connectors exist)
- [ ] ATS / https relay; cleartext only loopback for `wrangler dev`
- [ ] Threat notes: webhook SSRF (https only), feedback PII retention 30 days

### Privacy nutrition labels (App Privacy)
- [ ] Camera — only when user asks / live features; glasses light is Meta’s
- [ ] Microphone — speech
- [ ] Motion / fitness — glasses IMU for gestures (owner build); not sold
- [ ] Product interaction / diagnostics — opt-in telemetry; beta feedback redacted
- [ ] Contact info — only if account/support later requires it

### App Privacy Manifest (`PrivacyInfo.xcprivacy`)
- [ ] Declare Required Reason APIs actually used
- [ ] Tracking = false unless a real tracker ships (default: none)

### Review notes for DAT / Meta
- [ ] Name: **Phoenix Fox** — no Meta/Ray-Ban in app name or icon
- [ ] Compatibility wording: “works with compatible AI glasses”
- [ ] Adventurer (or listed DeviceType) as primary test hardware
- [ ] Capture light: we never attempt to disable; camera only on explicit use
- [ ] Experimental DAT (motion, on-glasses speech, …): owner/TestFlight channels only until Meta marks production-safe
- [ ] Wearables Developer Center release channel + Integration Review when Meta opens submissions

### Screenshots
- [ ] Phone UI: talk, settings, accessibility — no real API keys visible
- [ ] Do not show Meta AI app UI as if it were ours
- [ ] Optional: Display mockups labeled “Ray-Ban Display — future” only if accurate

### Meta Acceptable Use Policy (discovery / publishing)

Meta’s FAQ: all integrations and apps must comply with the **[Meta Wearables Developer Acceptable Use Policy](https://wearables.developer.meta.com/)** (linked from the FAQ “Publishing & Discovery” section). Discovery surfaces are coming in the Meta AI app and on Ray-Ban Display; submissions will open later via the Wearables Developer Center.

Before any discovery listing or Connector:

- [ ] Read and retain the current AUP text (date stamp in the PR / release notes)
- [ ] No prohibited categories (weapons, covert surveillance, deception, scraping Meta AI, etc. — verify against live AUP)
- [ ] No implication of Meta sponsorship or “official Meta AI”
- [ ] Camera / mic / motion uses match disclosed purpose; no always-on silent capture
- [ ] Child-directed / sensitive verticals: follow AUP + Apple rules or stay out
- [ ] Connector tools (see [META_AI_CONNECTOR_PLAN.md](META_AI_CONNECTOR_PLAN.md)) allow-listed and user-consented
- [ ] Web App (see [DISPLAY_WEB_APP_PLAN.md](DISPLAY_WEB_APP_PLAN.md)) follows Web App + AUP rules when built
- [ ] Account ready in Wearables Developer Center for submission timing announcements

## Related

- [GLASSES_SDK.md](GLASSES_SDK.md) — DAT 1.0.1 capabilities, motion, Mock Device Kit
- [DISPLAY_WEB_APP_PLAN.md](DISPLAY_WEB_APP_PLAN.md) — Display-agnostic cards → future Web App
- [META_AI_CONNECTOR_PLAN.md](META_AI_CONNECTOR_PLAN.md) — Hey Meta → Phoenix Fox bots
- [APP_STORE_PLAN.md](APP_STORE_PLAN.md) — Public sale blockers
