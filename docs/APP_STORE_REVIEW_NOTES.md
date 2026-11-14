# App Review notes — Phoenix Fox

Paste into App Store Connect → App Review Information → Notes.

**Reviewed against audit dated 14 November 2026.** See `docs/APP_STORE_REVIEW_AUDIT.md`.

---

## What this app is

Phoenix Fox is a hands-free voice assistant for compatible AI glasses (Meta Wearables Device Access Toolkit). The wake word inside the app is “Jarvis”. The App Store name is Phoenix Fox (Cinder & Crown LLC). It is **not** a Meta-branded or Ray-Ban-branded product.

## Demo without glasses (required path for reviewers)

1. Install the build and complete or skip onboarding (glasses can be skipped).
2. Open **Settings → Privacy & Data**.
3. Turn on **App Review demo**.
4. Accept **Cloud AI data sharing** only if you will paste a cloud key; otherwise leave consent off and use on-device / demo replies.
5. Return to Home. A banner shows that demo mode is on.
6. Tap the orb (or enable the mic) and try:
   - “What time is it”
   - “What can you do”
   - “Help”
7. Speech plays on the phone speaker. No glasses required.

Optional hardware path (if a Meta release channel and Adventurer / Ray-Ban Meta are available to the reviewer): pair in Meta AI, open Phoenix Fox, say “Jarvis, what time is it” — reply should come from the glasses speakers.

## Accounts

Phoenix Fox does **not** create a Cinder & Crown account. Optional sign-in is only to **third-party** AI subscriptions the user already has (for example SuperGrok or ChatGPT). Sign out is on each provider’s settings screen. **Erase all data on this phone** is under Privacy & Data.

## AI / privacy

- On-device path does not send prompts to Cinder & Crown.
- Cloud providers receive prompts/photos only after the user pastes their own key (or OAuth) **and** accepts Cloud AI data sharing consent.
- Privacy policy: in-app under Privacy & Data. Public URL: *(host and paste URL here before sale)*.

## In-app purchases

This binary ships with selling **off** unless `PHOENIX_FOX_STORE=YES` and a privacy policy URL are configured. Accessibility features and on-device models are never locked behind IAP.

## Background modes

- **audio** — wake word listening and spoken replies.
- **bluetooth-central** — Meta DAT device discovery/control.
- **external-accessory** — Meta protocol `com.meta.ar.wearable` (required by current DAT camera path; see MFi note below).
- **location** — walking directions and place reminders the user enables.
- **remote-notification** — optional relay push for the user’s own assistants.

## MFi / External Accessory

The binary declares `com.meta.ar.wearable` because Meta’s Wearables DAT currently requires it for this integration. As of Meta staff guidance in Discussion #313 (September 2026) and the iOS integration guide (checked 14 November 2026), Meta is **not** issuing PPIDs for third-party App Store apps yet. If this submission is a TestFlight-only / release-channel build, no PPID is required. For a public App Store binary, Meta must authorize the plan or provide an EA-free toolkit path before approval is possible.

## Encryption

Uses only standard HTTPS and on-device CryptoKit. Export compliance: exempt / non-exempt encryption flag is **No** (`ITSAppUsesNonExemptEncryption = false`).

## Contact

Use the App Review contact phone/email on this record for demo credentials or questions.
