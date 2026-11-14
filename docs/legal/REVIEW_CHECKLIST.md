# App Store and Google Play review checklist

> **Draft prepared for review; have a licensed attorney review before publishing.**

## Summary

- **Status key:** **Done** = in place now. **Code** = needs a code change. **Nicholas** = needs a decision or an account action from Nicholas.
- **Biggest blockers, in order:** (1) Meta still blocks App Store distribution of glasses apps (MFi), (2) the Apple Developer account must move from Individual to **Organization (Cinder and Crown LLC)**, (3) no consent screen before data goes to a third-party AI, (4) the face-recognition consent and auto-delete changes aren't built yet, (5) the privacy policy isn't hosted or linked in the app, (6) FluidAudio pulls GPL-derived data into the app.
- TestFlight beta testing isn't blocked by any of these.

---

## Decisions recorded (14 Nov 2026)

1. **Publisher:** Cinder and Crown LLC, a Texas limited liability company, Dallas, TX. Mailing address: [LLC MAILING ADDRESS — TO PROVIDE]. Apple account conversion: A29.
2. **Privacy contact:** privacy@cinderandcrown.com (**being set up**: confirm it receives mail before anything is published).
3. **Face recognition:** kept, with strict consent and auto-delete, default off in release builds until attorney sign-off (A8, C2).
4. **Meta DAT telemetry:** off (C4, G12).
5. **ChatGPT-subscription and SuperGrok sign-ins:** removed from store builds. API keys only (A21, C12).

## A. Host the policy at a public URL

| # | Item | Status |
|---|---|---|
| P1 | **Recommended (free, simplest): GitHub Pages from this public repo.** Repo Settings > Pages > "Deploy from a branch" > `main` > `/docs`. The pages become `https://cinderandcrown.github.io/phoenix-fox/legal/PRIVACY_POLICY` (GitHub's Jekyll renders Markdown as HTML). Publish **clean copies** with the draft banner, brackets, and code notes removed, after attorney review, for example `docs/legal/public/privacy.md`, `terms.md`, `disclaimers.md`. Optional: a custom domain like `legal.cinderandcrown.com` with a CNAME record. Alternative: a page on cinderandcrown.com. **Nothing has been published.** | Nicholas |
| P2 | Put the privacy policy URL in App Store Connect (App Privacy > Privacy Policy URL) and Play Console (App content > Privacy policy) | Nicholas |
| P3 | Put the Terms of Use URL in App Store Connect > App Information > **License Agreement** (custom EULA), and in the app description | Nicholas |
| P4 | Set `StoreCatalog.privacyURL` and `StoreCatalog.termsURL` (`OpenVision/Services/Store/Core/StoreCatalog.swift`, lines 48-51). The app refuses to sell until `privacyURL` is set | Code |

## B. In-app link locations

| # | Where | What | Status |
|---|---|---|---|
| B1 | **Settings > About** (new section at the bottom of `Views/Settings/SettingsView.swift`) | Privacy Policy, Terms of Use, Disclaimers, **Licenses / Acknowledgements**, contact email, app version, the "independent app" line from DISCLAIMERS section 1 | Code |
| B2 | **Settings > Plan** (`Views/Settings/PlanView.swift`) | Terms of use and Privacy policy links next to the subscribe buttons, plus the auto-renew text. The text and terms link are **Done**. The privacy link appears only once `privacyURL` is set | Code (P4) |
| B3 | **Onboarding**, last step (`Views/Onboarding/OnboardingView.swift`, `Core/OnboardingFlow.swift`) | One line: "By continuing you agree to the Terms of Use and Privacy Policy," with links, plus "You must be 18 or older." | Code |
| B4 | **AI consent screen** (section C) | Links to our Privacy Policy and the provider's | Code |
| B5 | **Face recognition toggle** (`Views/Settings/AccessibilitySettingsView.swift`, line ~87) | Short notice and a link to Privacy Policy section 5 | Code |
| B6 | **Licenses screen** (Settings > About > Licenses) | Shows the bundled `NOTICE` and `THIRD_PARTY_NOTICES.md` (MIT, BSD, and Apache-2.0 all require this) | Code |
| B7 | Workshop medication and allergen screens; emergency contact setting | The disclaimer copy from DISCLAIMERS sections 3.2 and 3.4 | Code |

## C. Consent screen copy for AI data sharing

Show this **before the first request to each cloud provider** (xAI, OpenAI, Anthropic, Google, and any relay or gateway), on the phone screen. Save the choice with a date, per provider. Let users withdraw it at **Settings > [provider] > Data sharing**. Until a provider is allowed, use on-device AI only. This meets Apple guideline **5.1.2(i)** (disclose, and get explicit permission before sharing personal data with third parties, including third-party AI) and Google Play's **prominent disclosure and consent** rule.

> **Title:** Send to Grok (xAI)?
>
> **Body:** To answer you, Phoenix Fox sends xAI:
> • what you say, as text, and recent conversation
> • pictures from your glasses, when you ask Jarvis to look
> • your saved memories and custom instructions
>
> xAI handles this under its own privacy policy and your xAI account. Phoenix Fox doesn't keep a copy on any server. Your face data and medication log are never sent.
>
> **[ Allow ]**   **[ Not now, stay on this iPhone ]**
>
> Privacy Policy · xAI Privacy Policy · You can change this in Settings.

Variants:

- **Live mode (OpenAI or Gemini):** add the bullet "• your voice and camera video, streamed for as long as live mode is on".
- **Cloud voice:** "• Jarvis's replies, to turn them into speech".
- **Guide mode cloud descriptions:** "Guide mode can send pictures of what's in front of you to [provider] when this iPhone can't describe them. [Allow] [Keep descriptions on this iPhone]".
- **Your own assistant (relay):** "Phoenix Fox sends what you say, recent conversation, and pictures you include to the relay at [host], and from there to the assistants it's set up for. Whoever runs that relay is responsible for it."
- **Face recognition, wearer opt-in (on screen):** "Face recognition helps you know who's in front of you. It only recognizes people who agree, in their own voice, to be saved. Face data stays encrypted on this iPhone, is never sent anywhere, and is deleted after 30 days without a match. You're responsible for getting each person's consent. [Turn on] [Not now]"
- **Face recognition, enrolled person's consent (spoken to that person, through the glasses speaker or phone):** "Hi, I'm Jarvis, an assistant on [wearer]'s glasses. May I save your face on this phone so [wearer] can recognize you? It stays on this phone only, is never uploaded, and is deleted after 30 days if you're not seen, or any time you ask [wearer]. Please say 'yes, I agree' or 'no'." Save only on a clear yes in a voice other than the wearer's (or with the wearer confirming the other person answered). Store the time of that yes.
- **Spoken fallback** (glasses only, phone in pocket; use only to *re-confirm* a consent already given on screen): "To answer that, I'd send what you said, and the picture, to Grok. Say allow, or say no to stay on the phone."

**Accessibility:** the screen must work with VoiceOver, with the buttons labeled exactly as shown.

## D. Apple App Review checklist

| # | Guideline | Item | Status |
|---|---|---|---|
| A1 | 5.1.1(i) | Privacy policy link in App Store Connect **and** easy to find in the app | Nicholas (P1, P2) + Code (B1) |
| A2 | 5.1.1(i) | The policy says what's collected, how, all uses, that third parties give equal protection, retention and deletion, and how to withdraw consent and request deletion | Done (draft) |
| A3 | 5.1.1(ii) | Purpose strings are specific (see APPLE_PRIVACY_LABEL.md section 5) | Done |
| A4 | 5.1.1(ii) / 5.1.2(i) | **Explicit consent before sending personal data to a third-party AI** | **Code** (section C) |
| A5 | 5.1.1(iii) | Data minimization: Guide mode cloud descriptions are **on by default** (`Services/Accessibility/Core/AccessibilitySettings.swift`, line 19). Make it off by default, or ask the first time | Code |
| A6 | 5.1.1(iv) | Features still work, with fallbacks, if a permission is refused. Code paths give spoken fallbacks | Done (verify in the demo) |
| A7 | 5.1.1(v) | No account required. Account deletion doesn't apply. Store builds use pasted API keys only (decision 5) | Done (after C12) |
| A8 | 5.1.1(viii) / 5.1.2 | **Face recognition: decided to keep it**, with: wearer opt-in; a **separate, timestamped spoken consent from each enrolled person**; on-device only; encrypted and excluded from backup; **auto-delete after 30 days without a match (configurable down to 1 day)** and immediately on request; strangers never stored; forget by voice and in Settings. **Default off in release builds until an attorney signs off.** Policy section 5 and Terms section 6A are written to match. Explain the consent flow in the review notes | **Code (C2)** + attorney sign-off |
| A9 | 5.1.2(ii)-(iii) | No repurposing, profiling, or ads | Done |
| A10 | 5.1.3 | Medication log isn't HealthKit and makes no health claims. Disclaimer shown | Done + Code (B7) |
| A11 | 5.1.4 | Not a kids app. Set the age rating to **18+** in App Store Connect (AI chat, user-generated content, camera) | Nicholas |
| A12 | 5.1.5 | Location is used only for features the user asks for. "Always" and background location are explained in the review notes | Nicholas (notes) |
| A13 | 2.5.4 | Each background mode (`audio`, `bluetooth-central`, `bluetooth-peripheral`, `external-accessory`, `location`, `remote-notification`) explained in the review notes. Meta's SDK requires the Bluetooth and accessory modes | Nicholas (notes) |
| A14 | 2.5.14 | Recording needs explicit consent and a clear indicator: the glasses' capture light (hardware), the on-screen recording state (`Views/VoiceAgent/VoiceAgentViewModel.swift` `isRecording`), the Guide mode notice, and a spoken "camera on". Live captions with "keep transcripts" should show a visible indicator while saving | Done / Code (caption indicator) |
| A15 | 2.5.2 | ML weights downloaded at runtime are data, not code | Done |
| A16 | 2.1 | **Demo mode** so the reviewer can test without glasses (Meta's Mock Device Kit or recorded frames), plus a reviewer path that doesn't need the reviewer's own API key | Code + Nicholas (review notes) |
| A17 | 2.3 | Accurate metadata: needs compatible AI glasses and a provider key for cloud AI. Accessibility features are free. Screenshots must not show features that are off in the build | Nicholas |
| A18 | 3.1.1 / 3.1.2 | StoreKit subscriptions, restore button, auto-renew disclosure, Terms and Privacy links on the paywall | Done except P4 |
| A19 | 3.1.2 | A custom EULA in App Store Connect, or keep Apple's standard EULA. **We chose custom** (TERMS_OF_USE.md) | Nicholas (P3) |
| A20 | 4.8 | Sign in with Apple isn't required (no app account. Provider sign-ins are only for that provider's service) | Done |
| A21 | **5.2.2** | Third-party service authorization: **decided to remove ChatGPT-subscription and SuperGrok sign-ins from store builds.** Users paste API keys. Gate the sign-in UI and OAuth code behind the owner/TestFlight flavor, or delete it (`Services/AIBackend/ChatGPTSubscription.swift`, `Services/AIBackend/GrokService.swift`, `Services/OAuth/*`, `Views/Settings/OpenAISettingsView.swift`, `Views/Settings/GrokSettingsView.swift`) | **Code (C12)** |
| A22 | 5.2.1 | No "Meta", "Ray-Ban", or "Oakley" in the name, subtitle, or icon. No Marvel, "Iron Man", or "J.A.R.V.I.S." in marketing | Nicholas |
| A23 | 5.2.3 / Meta terms | Meta Integration Review, and **Meta lifting the App Store / MFi block** (`docs/APP_STORE_PLAN.md`) | Nicholas / Meta |
| A24 | Privacy label | Answer as in APPLE_PRIVACY_LABEL.md (set A after the Meta opt-out) | Nicholas + Code |
| A25 | Privacy manifest | Add the System Boot Time reason `35F9.1`, fill in the collected types, and generate Xcode's Privacy Report | Code |
| A26 | ATS | Remove `NSAllowsArbitraryLoads`, or justify it in the review notes (`Resources/Info.plist`) | Code |
| A27 | Export compliance | `ITSAppUsesNonExemptEncryption = false` | Done |
| A28 | EU Digital Services Act | If the app is offered in the EU, App Store Connect needs a **trader status** declaration. As a trader, the **LLC's** address, phone, and email are shown publicly on the EU store page ([LLC MAILING ADDRESS — TO PROVIDE]). Decide whether EU storefronts are included at launch | **Nicholas** |
| A29 | Legal entity | **Publisher is Cinder and Crown LLC** (decided). The Apple Developer account is currently enrolled as an **Individual** (Nicholas Will) and **must be converted to an Organization account** in the LLC's legal name. That needs a **D-U-N-S number for Cinder and Crown LLC** (free from Dun & Bradstreet through Apple's D-U-N-S lookup), legal binding authority, and a website on the LLC's domain. The App Store seller name changes to the LLC after conversion. **The Meta Wearables Developer Terms should also be accepted by the LLC**, and the Meta app (ID in `Info.plist`) owned by the LLC's Meta developer organization. Google Play: register an **organization** developer account (also needs the D-U-N-S) | **Nicholas** |

## E. Google Play checklist (future Android)

| # | Policy | Item | Status |
|---|---|---|---|
| G1 | User Data | Privacy policy in Play Console and in the app | Nicholas + Code |
| G2 | User Data, prominent disclosure | The consent screen in section C | Code |
| G3 | Data safety | Answers in GOOGLE_PLAY_DATA_SAFETY.md | Nicholas |
| G4 | Permissions | Runtime camera and mic requests in context. Foreground service types and the Play declaration | Code (Android) |
| G5 | Location | Avoid background location (drop arrival reminders in Android v1). If kept: declaration form, video, and in-app disclosure before the prompt | Code + Nicholas |
| G6 | SMS / Call Log | Don't request restricted permissions. Use dial and send intents | Code (Android) |
| G7 | Photo and Video Permissions | Use the photo picker | Code (Android) |
| G8 | **AI-Generated Content** | An in-app "report this answer" option that works without leaving the app | Code (both platforms recommended) |
| G9 | Account deletion | Not required (no accounts). Add it if accounts are introduced | Done |
| G10 | Health apps declaration | Complete it accurately (the medication log is health-adjacent) | Nicholas |
| G11 | Target audience | 18+ only. IARC questionnaire | Nicholas |
| G12 | Meta telemetry | **Off (decided).** `ANALYTICS_OPT_OUT` meta-data in the manifest | Code (Android) |
| G13 | Developer account | Register an **organization** account for Cinder and Crown LLC (needs the D-U-N-S number, see A29) | Nicholas |

## F. Code-side gaps found (file paths)

| # | Gap | File(s) | Severity |
|---|---|---|---|
| C1 | No consent before sending prompts, images, audio, or memories to cloud AI providers | `Services/Brain/Providers/ProviderRouter.swift`, `Services/Brain/Providers/*`, `Services/AIBackend/*`, `Views/Onboarding/Core/OnboardingFlow.swift` (no consent step) | **Blocker** |
| C2 | **Face recognition: build the decided safeguards.** Today the code (a) takes the *wearer's* yes as the other person's consent (`AccessibilityCoordinator.swift`, line ~150), so it must instead ask the enrolled person directly and keep a timestamp of *their* spoken yes (store a consent record per person; `FaceRecord.consentAt` exists). It also (b) has no auto-delete: add a 30-day default, a 1-30 day setting, and a sweep at launch and on each match (`AccessFaces.swift`, `FaceLedger.swift`). (c) The owner profile turns it on (`GlassesCapabilitySettings.swift:112`): keep it **off in release builds** until attorney sign-off. (d) Add a per-person Delete in Settings (`AccessibilitySettingsView.swift`). Confirm (e) templates of unmatched faces are never written (true today: `identify` only compares) | **Blocker (legal)** |
| C3 | Guide mode cloud descriptions on by default | `Services/Accessibility/Core/AccessibilitySettings.swift:19` | High |
| C4 | **Turn Meta DAT telemetry off (decided):** add `MWDAT > Analytics > OptOut = YES` | `Resources/Info.plist` (`MWDAT` dict), then keep `PrivacyInfo.xcprivacy` consistent | High |
| C5 | Privacy manifest is missing the System Boot Time API (`systemUptime`), and collected types are empty | `Resources/PrivacyInfo.xcprivacy`, plus uses in `Managers/GlassesManager.swift`, `Services/Accessibility/SoundAlertService.swift`, `Services/Glasses/GlassesControlSession.swift` | High |
| C6 | No privacy policy URL, and Terms points to Apple's standard EULA | `Services/Store/Core/StoreCatalog.swift:48-51` | High |
| C7 | No About / Privacy / Licenses screen in Settings | `Views/Settings/SettingsView.swift` | High |
| C8 | No single "Delete all my data" control (conversations, memories, documents, transcripts, faces, workshop, keys) | `Views/Settings/*`, `Managers/ConversationManager.swift`, `Services/Accessibility/AccessStore.swift` | Medium |
| C9 | User speech and prompts written to the device log | `Services/Voice/VoiceCommandService.swift:575, 721`; `Services/AIBackend/CloudChat.swift:140`; `Services/GeminiLive/GeminiLiveService.swift:384`; `Services/OpenClaw/OpenClawService.swift:415, 580, 629`; `Services/GemmaLocal/GemmaLocalService.swift:745`. Use `Logger` with `privacy: .private`, or the `LogRedactor` on the beta-feedback branch | Medium |
| C10 | Conversation history stored as plain JSON in `Documents/` (backed up), unlike the sealed accessibility data | `Managers/ConversationManager.swift:36-190` | Medium |
| C11 | `NSAllowsArbitraryLoads = true` | `Resources/Info.plist` | Medium |
| C12 | **Remove ChatGPT-subscription and SuperGrok sign-ins from store builds (decided)**; API keys only | `Services/AIBackend/ChatGPTSubscription.swift`, `Services/AIBackend/GrokService.swift`, `Services/OAuth/*`, `Models/AppSettings.swift` (`openAIAuthMode`, `grokAuthMode`), `Views/Settings/OpenAISettingsView.swift`, `GrokSettingsView.swift` | High |
| C13 | FluidAudio floats to 0.18.3, which bundles GPL-3.0-derived and CC-BY-SA data | `project.yml` (`FluidAudio: from: "0.15.5"`) | **Blocker (license)** |
| C14 | A non-commercial model (Qwen2.5-3B, Qwen Research License) is offered | `Services/GemmaLocal/GemmaLocalService.swift:59` | High (paid app) |
| C15 | The owner's relay address is compiled into every build as the default | `Services/Relay/RelayClient.swift:183` (`defaultAddress`). `docs/APP_STORE_PLAN.md` says not to put it in the binary | Low (needs the owner's token anyway) |
| C16 | `NSCameraUsageDescription` describes the glasses camera, but no phone camera use was found | `Resources/Info.plist` | Low |
| C17 | No in-app "report this answer" for AI output | — | Medium (required on Play) |
| C18 | Beta feedback reports are kept 30 days on the relay (branch, disclosed) | `cursor/beta-feedback-diagnostics-df33`: `relay/src/handle.ts` (`FEEDBACK_TTL_MS`), `Services/Diagnostics/BetaFeedbackService.swift` | Info |
| C19 | `Package.resolved` isn't committed on main, and mlx-swift is pinned to a branch | `project.yml`, `PhoenixFox.xcodeproj` | Medium |

**Confirmed fine:** API keys are in the Keychain (`Managers/SettingsSecrets.swift`). Accessibility and workshop data are AES-GCM sealed with a this-device-only key and excluded from backup (`Services/Accessibility/AccessStore.swift`). The medication log is never sent. Sound alerts run on device. Calls, texts, and email go through iOS composers, and the emergency call needs confirmation (`AccessibilityCoordinator.swift:49`). The Guide mode safety notice needs a spoken yes. The relay deletes asks after 15 minutes and inbox messages after 24 hours (`relay/src/handle.ts`). No ads, analytics, ATT, or IDFA.

## G. Licenses (from THIRD_PARTY_NOTICES.md)

| # | Item | Status |
|---|---|---|
| L1 | **In-app Licenses / Acknowledgements screen** that shows `NOTICE` and `THIRD_PARTY_NOTICES.md`, reachable from Settings > About. It satisfies MIT (OpenVision, kokoro-ios, WhisperKit, mlx, ZIPFoundation, yyjson, EventSource), BSD-2 (fastcluster, if FluidAudio 0.18.x stays), Apache-2.0 §4(a)/(d) (including the swift-crypto NOTICE), and the Gemma terms | Code |
| L2 | Pin FluidAudio 0.15.5, or turn off its `TTS` trait | Code |
| L3 | Remove Qwen2.5-3B from store builds | Code |
| L4 | Decide on Gemma 2 2B (keep with its terms, or drop it) | Nicholas |
| L5 | SPDX headers on every source file, and the license field in `relay/package.json` | **Done (this PR)** |
| L6 | NOTICE names the vendored packages and the swift-crypto notice | **Done (this PR)** |

## H. App Review notes (draft to paste in App Store Connect)

> Phoenix Fox is a hands-free assistant for compatible AI glasses, using Meta's Wearables Device Access Toolkit. A **demo mode** (Settings > Demo) lets you try every screen without glasses [CODE: build this]. Accessibility features (reading text, sound alerts, captions, Guide mode) are free and run on the device. Cloud AI uses the user's own provider key. Before anything is sent, the app shows a consent screen naming the provider. [For review, use: DEMO KEY PROVIDED SEPARATELY / demo mode.]
>
> Background modes: **audio**, to keep listening for the wake word and to play spoken replies through the glasses while the phone is locked. **bluetooth-central, bluetooth-peripheral, external-accessory**, required by Meta's toolkit to keep the glasses connected. **location**, for spoken turn-by-turn walking directions while the phone is locked, started only by the user. **remote-notification**, to tell the user when a task they asked their own assistant to do is finished. "Always" location is used only for arrival reminders the user creates, and walking directions. iOS shows the location arrow.
>
> The glasses' capture light is on whenever the camera is in use, and the app can't turn it off. No data is collected by the developer (Cinder and Crown LLC). There's no account, and no ads or tracking. Meta's toolkit telemetry is switched off. Cloud AI uses API keys the user pastes. Face recognition is off by default. If enabled, it asks each person for their own spoken consent, stays on the device, and auto-deletes after 30 days without a match.
