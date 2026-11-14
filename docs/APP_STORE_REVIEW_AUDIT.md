# App Store Review audit — Phoenix Fox

**Audited:** 14 November 2026  
**Publisher:** Cinder & Crown LLC · Bundle ID `com.cinderandcrown.phoenixfox`  
**Scope:** Apple [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) as they apply to this binary, plus Meta Wearables DAT publishing constraints that Apple will hit first.

This is the living checklist for a public App Store submission. Severity is **Blocker** (will reject or cannot ship), **High** (likely reject), **Medium** (common ask / incomplete), **Low** (polish / documentation). Each item names a **fix**. Code-side fixes land in the same PR as this file; human / account work is listed at the end.

Related: [APP_STORE_PLAN.md](APP_STORE_PLAN.md), [BUSINESS_MODEL.md](BUSINESS_MODEL.md), [APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md), [PRIVACY_POLICY.md](PRIVACY_POLICY.md).

---

## Verdict

**Not ready for a public App Store sale today.** Meta still will not authorize third-party apps that declare `com.meta.ar.wearable` on its MFi Product Plan, and Apple rejects that declaration without a PPID. Distribution remains **TestFlight + Meta release channel**. The rest of this audit hardens the binary so the next submission after Meta opens publishing is reviewable.

---

## Blockers

### B1 — MFi / PPID for `com.meta.ar.wearable` (Guideline 2.1 / MFi)

**Finding.** `Info.plist` declares `UISupportedExternalAccessoryProtocols` → `com.meta.ar.wearable` and `UIBackgroundModes` → `external-accessory`. Apple treats that as an MFi accessory protocol and asks for Meta’s Product Plan / PPID.

**Sources (cited dates):**

| Source | Date | What it says |
| --- | --- | --- |
| [meta-wearables-dat-ios Discussion #313](https://github.com/meta/meta-wearables-dat-ios/discussions/313) — alexsinkmeta | 27 Sep 2026 (thread) / reply in-thread | “DAT 1.0 doesn't change this yet. Meta isn't able to add third-party apps to its MFi Product Plan or issue PPIDs… submissions that declare `com.meta.ar.wearable` will still hit this review requirement.” TestFlight + release channel: no PPID needed. |
| [Issue #266](https://github.com/meta/meta-wearables-dat-ios/issues/266) — alexsinkmeta | 10 Aug 2026 | No App Store publishing announced; no waitlist; declaring `com.meta.ar.wearable` triggers MFi. |
| [Meta Wearables FAQ — Publishing & Discovery](https://developers.meta.com/wearables/faq/) | fetched 14 Nov 2026 | DAT 1.0 stable (rollout from 30 Sep 2026). Discovery/submission “soon”; create a Wearables Developer Center account. Does **not** say public App Store + PPID is open. |
| [iOS build-integration guide](https://wearables.developer.meta.com/docs/develop/dat/build-integration-ios/) | fetched 14 Nov 2026 | **App Store Submission Warning:** publishing not currently supported; ExternalAccessory → MFi / privacy-manifest rejection. Recommended path for *future* readiness: Wi-Fi camera + Bluetooth LE **without** External Accessory (see also Discussion #297 staff note). |

**Fix (human / Meta).** Wait for Meta to open App Store publishing and either (a) authorize this bundle ID on Meta’s MFi plan and issue a PPID, or (b) ship a DAT path that does not declare `com.meta.ar.wearable`. Until then: TestFlight only.  
**Fix (code, preparatory).** Keep EA declaration for TestFlight builds that talk to Adventurer today. Document the strip-EA App Store variant in review notes; do not remove EA from the shipping TestFlight Info.plist while the glasses path still needs it. Experimental DAT capabilities stay owner-gated (see B2).

---

### B2 — Experimental / non-publishable DAT modules in a release binary

**Finding.** The app links `MWDATDisplay`, `MWDATInputs`, `MWDATSpeech`, `MWDATMotion` (and tests may link `MWDATMockDevice`). Meta labels several capabilities **beta / experimental** (controls, capture button, head gestures, high-resolution stills, ambient audio, on-glasses speech). Meta’s terms: production apps must not depend on experimental toolkit features.

**Fix (code — done / verify).** Runtime gate via `BuildFlavor.allowsExperimental` and `GlassesCapabilitySettings.allowed(in:)`: standard builds force beta switches **off** regardless of saved settings. Full-sensor photo path requires owner build. Workshop features similarly gated.  
**Fix (human).** Ship App Store / public channel builds with `PHOENIX_FOX_OWNER_BUILD=NO`. Owner TestFlight may keep experimental for Adventurer beta channel only.

---

## High

### H1 — Guideline 2.1 completeness: demo without glasses

**Finding.** Reviewers typically have no Ray-Ban / Meta glasses and no Meta release channel. Without a demo path the app looks incomplete (connect glasses or nothing).

**Fix (code).** `ReviewerDemo` mode: Settings → Privacy & Data → **App Review demo**. Scripted hands-free answers (time, what can you do, accessibility) on the phone mic/speaker; banner while on. Pasteable steps in [APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md).  
**Fix (human).** Attach review notes in App Store Connect; optionally add a short screen recording of glasses + Adventurer as an App Review attachment when hardware is required for a claim.

---

### H2 — Guideline 5.1.1 privacy policy URL + in-app link

**Finding.** `StoreCatalog.privacyURL` was `nil`. No in-app privacy document. Selling is correctly blocked (`missingBeforeSale`), but App Review still expects a policy for the app itself.

**Fix (code).** In-app **Privacy policy** screen sourced from [PRIVACY_POLICY.md](PRIVACY_POLICY.md); Settings → Privacy & Data.  
**Fix (human).** Host the same text at a stable HTTPS URL (intended: `https://phoenix-fox-links.cinderandcrown.workers.dev/privacy`), set `StoreCatalog.privacyURL`, fill App Store Connect Privacy Policy URL, complete the privacy nutrition label to match the policy and `PrivacyInfo.xcprivacy`.

---

### H3 — Guideline 5.1.2(i) AI data-sharing consent

**Finding.** Cloud brains (Grok, Claude, OpenAI, Gemini, relay) can send transcripts and photos off-device with only a Keychain key paste — no explicit consent before first cloud send.

**Fix (code).** One-time **Cloud AI data sharing** consent sheet before the first cloud request; stored on device; withdraw in Privacy & Data (forces on-device / clears cloud use until re-accepted). Key-entry footers disclose that prompts and photos leave the phone to that vendor.  
**Fix (human).** Link each vendor’s privacy policy in the hosted privacy page; keep nutrition label aligned.

---

### H4 — Guideline 5.1.1 account deletion

**Finding.** Phoenix Fox does not create a Cinder & Crown cloud account. Local Keychain keys and on-device data exist. Apple still asks “how do I delete my account?” when sign-in of any kind appears (SuperGrok / ChatGPT OAuth).

**Fix (code).** Privacy & Data → **Erase all data on this phone** (settings reset, local stores) + copy that there is **no Phoenix Fox cloud account**; OAuth “Sign out” on provider screens.  
**Fix (human).** If a hosted account is ever added, ship a server-side deletion endpoint and link it within the app within the guideline window.

---

### H5 — Guideline 3.1 in-app purchase

**Finding.** StoreKit 2 plans exist but selling is off (`PHOENIX_FOX_STORE`, missing privacy URL, owner never sells). Accessibility and on-device brains are never paid features (`Plan` / `Access`) — correct for 3.1.1 / accessibility expectations.

**Fix (code).** Keep accessibility + on-device free in `Plan.swift`; do not unlock paid features without StoreKit when selling.  
**Fix (human).** Create subscription group/products in App Store Connect; turn `PHOENIX_FOX_STORE=YES` only after privacy URL + paid-apps agreements; never enable store on owner builds.

---

## Medium

### M1 — Guideline 4.2 minimum functionality

**Finding.** With glasses + wake word the app is a full assistant. Without glasses, value must still be obvious (phone mic, on-device answers, accessibility, settings).

**Fix (code).** Reviewer demo + onboarding that allows skipping glasses with a home Register banner (already present). Ensure demo answers prove utility without hardware.  
**Fix (human).** App Store screenshots and description lead with the hands-free glasses experience **and** show phone-only use; do not imply Meta sponsorship.

---

### M2 — User-generated content, AI moderation, reporting (Guideline 1.2 / UGC)

**Finding.** No public social feed. Local notes/skills/memories. Assistants can produce AI text. No in-app “report this reply” path.

**Fix (code).** Privacy & Data → **Report a concern** (mailto to publisher) for harmful AI output or privacy issues; copy that content is single-user / BYO.  
**Fix (human).** Monitor the support inbox; if multi-user UGC appears later, add block/filter and 24h moderation tooling.

---

### M3 — Background modes justification (Guideline 2.5.4)

**Finding.** Declared: `audio`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`, `location`, `remote-notification`.

| Mode | Used for | Action |
| --- | --- | --- |
| `audio` | Wake word / TTS / conversation session | Keep; justify in review notes |
| `bluetooth-central` | Meta DAT BLE discovery/control | Keep (Meta requirement) |
| `bluetooth-peripheral` | No first-party advertise API | **Removed** from Info.plist |
| `external-accessory` | Meta `com.meta.ar.wearable` | Keep until Meta EA-free path; explain (B1) |
| `location` | Walking guide + place reminders | Keep; purpose strings present |
| `remote-notification` | Relay APNs inbox pull | Keep |

---

### M4 — Third-party AI key entry wording

**Finding.** Copy emphasized Keychain storage, not that prompts/photos are processed by the vendor.

**Fix (code).** Update Grok / OpenAI / Claude footers and onboarding paste copy to state clearly that requests (and photos you attach) are sent to that provider under their terms; keys stay in Keychain and are never logged.

---

### M5 — `NSAllowsArbitraryLoads`

**Finding.** Global ATS exception for local Hermes, custom OpenAI-compatible bases, WebSockets, self-hosted telemetry.

**Fix (code).** Keep `NSAllowsLocalNetworking`; leave arbitrary loads on for BYO HTTP endpoints; document in review notes. Prefer HTTPS in UI copy.  
**Fix (follow-up).** Narrow to exception domains once product URLs are fixed.

---

### M6 — Privacy nutrition label vs reality

**Finding.** `PrivacyInfo.xcprivacy` collects no data types (Cinder & Crown collects nothing). Cloud vendors the user configures receive data — that must appear in App Store Connect nutrition answers as data linked to the user / used for app functionality when the user opts into cloud AI.

**Fix (human).** Complete App Privacy answers to match [PRIVACY_POLICY.md](PRIVACY_POLICY.md). Revisit if first-party analytics are added.

---

### M7 — Purpose strings

**Finding.** Microphone, speech, camera, Bluetooth, local network, photos, location, calendars, reminders, contacts, Apple Music strings exist and are mostly plain-language.

**Fix (code).** Spot-check during consent work; tighten any string that undersells AI off-device use (camera / speech already OK). No empty strings.

---

## Low

### L1 — Export compliance

**Finding.** `ITSAppUsesNonExemptEncryption` = `false` (HTTPS + CryptoKit only). Correct for exempt encryption.

**Fix (human).** Answer the App Store Connect export questionnaire consistently (standard encryption only).

---

### L2 — Age rating

**Finding.** Unrestricted conversational AI + optional web search can surface mature content. No made-for-kids mode.

**Fix (human).** Age rating questionnaire: expect **12+** minimum; consider **17+** if unrestricted web/search stays on without a stronger safety filter. Not Made for Kids. Document choice in Connect.

---

### L3 — Naming / trademarks

**Finding.** Display name Phoenix Fox; wake word Jarvis is in-app only. Must not imply Meta / Ray-Ban sponsorship.

**Fix (human).** Listing copy: “works with compatible AI glasses”; no Meta/Ray-Ban in icon or subtitle.

---

## Code-side fixes in this change set

1. This audit + [APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md) + [PRIVACY_POLICY.md](PRIVACY_POLICY.md).
2. Reviewer demo mode (no glasses).
3. Cloud AI data-sharing consent + withdraw.
4. Privacy & Data settings: policy, erase local data, report concern, demo toggle.
5. Stronger third-party key / onboarding disclosure copy.
6. Remove unused `bluetooth-peripheral` background mode.
7. Unit tests for consent gate and reviewer demo replies.

---

## Human / account checklist (not done by code alone)

1. **Meta:** Wait for App Store publishing / PPID or EA-free DAT path; Integration Review; release channel for Adventurer. Watch Discussion #313 / Wearables Developer Center (as of 14 Nov 2026 still blocked).
2. **Host** privacy policy (+ terms if replacing Apple EULA); set `StoreCatalog.privacyURL`; deploy to the links worker.
3. **App Store Connect:** privacy policy URL, nutrition label, age rating, export compliance answers, review notes paste, subscription products, paid apps agreement.
4. **Support inbox** for Report a concern mail.
5. **Screen recording** of glasses session for review attachment when claiming hardware features.
6. **Legal review** of privacy policy and subscription copy before first paid build.
7. Confirm `PHOENIX_FOX_OWNER_BUILD=NO` and store flag policy for the App Store binary.
