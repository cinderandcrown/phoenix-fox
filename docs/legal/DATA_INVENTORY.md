# Phoenix Fox data inventory

> **Draft prepared for review; have a licensed attorney review before publishing.**

**Summary.** This is the evidence base for every other document in this folder. Each row was traced to code on `main` at commit `a56d1bf` (PR #11 merged), plus the open branches named at the end. Phoenix Fox has **no user accounts and no backend of its own for the public app**. Most data stays on the phone. Data leaves the phone only when it goes to a service the user turns on and configures (an AI provider with the user's own key or sign-in, a self-run relay or gateway, a web search service, Apple's own services), or to Meta through the glasses SDK. The one big exception to "nothing sensitive is kept" is **optional, on-device face recognition**, which stores face prints on the phone.

If code changes, this table must be updated before the policy or the App Store answers are changed.

## Legend

- **Where:** *Device* = stays on the iPhone. *Sent* = leaves the phone.
- **Linked:** whether the recipient can tie it to a person (an account, API key, or device token).
- **Tracking:** in Apple's sense (linking with other companies' data for advertising, or sharing with data brokers). The answer is **No** for every row.

## On-device data

| Data | Source | Where | Purpose | Retention | Code |
|---|---|---|---|---|---|
| Voice audio (wake word, commands) | Glasses mic (mono 16 kHz over Bluetooth HFP) or phone mic | Device by default. Apple speech recognition runs on device when the phone supports it **and** the on-device setting is on. Otherwise Apple's server recognizer is used (see sent data) | Wake word, transcribe what the user says | Audio buffers are not saved. Discarded after recognition | `Services/Voice/VoiceCommandService.swift` (lines ~330-335 `requiresOnDeviceRecognition`), `Services/Audio/AudioCaptureService.swift`, `Services/Speech/UtterancePCMBuffer.swift` |
| On-device speech to text (Whisper) | Mic | Device | Transcription | Not saved | WhisperKit, `project.yml` |
| Voice activity detection | Mic | Device (Silero VAD on the Neural Engine via FluidAudio) | End-of-speech detection | Not saved | `project.yml` (FluidAudio), `Services/Voice/SpeechActivityDetector.swift` |
| Sound alerts (sirens, alarms, doorbell) | Mic, plus glasses stream audio in owner builds | Device (Apple SoundAnalysis) | Accessibility alerts for Deaf and hard-of-hearing users | Nothing recorded | `Services/Accessibility/SoundAlertService.swift` |
| Live captions / saved transcripts | Mic (may include other people's speech) | Device. Saved only if "keep transcripts" is on (off by default, on in the owner build) | Captions; recall | Until the user deletes them. AES-GCM sealed, excluded from backup | `Services/Accessibility/LiveCaptions.swift`, `Services/Accessibility/AccessStore.swift` |
| Camera frames and photos | Glasses camera via Meta Wearables DAT (stream frames; Wi-Fi hotspot for bandwidth) | Device unless sent to a cloud AI (see below) | "Look", read text, money, labels, colors, scene description | Frames are transient. Workshop walk-through photos are saved sealed until erased | `Managers/GlassesManager.swift`, `Services/Glasses/WearablesSDK.swift`, `Services/Accessibility/AccessVision.swift`, `Services/Workshop/WorkshopCoordinator.swift` (~line 223) |
| On-device text, barcode, people, animal, scene recognition | Camera frames | Device (Apple Vision) | Accessibility reading features | Not saved | `Services/Accessibility/AccessVision.swift` |
| **Face prints (biometric)** | Glasses camera, Apple Vision `VNDetectFaceRectanglesRequest` + `VNGenerateImageFeaturePrintRequest` on the face crop | Device only. Never sent | Recognize people the wearer saved by name, after the wearer says the person agreed | Until the wearer says "forget [name]'s face" / "forget all faces" or deletes the app. **No automatic expiry.** Up to 5 prints per person. Stored with name, consent date, last-seen date. AES-GCM sealed, key in Keychain (this-device-only), excluded from backup | `Services/Accessibility/AccessFaces.swift`, `Services/Accessibility/Core/FaceLedger.swift`, `Services/Accessibility/AccessVision.swift` (~128-155), `Services/Accessibility/AccessibilityCoordinator.swift` (~146-160, 278, 380). Off by default (`Core/AccessibilitySettings.swift` line 21), **on in the owner build** (`Services/Glasses/Core/GlassesCapabilitySettings.swift` line 112) |
| Conversation history | Chats with the assistant | Device, `Documents/` (plain JSON with iOS default file protection). Included in the user's iCloud or computer backup | History tab | Until the user deletes conversations | `Managers/ConversationManager.swift` (~36-190) |
| Settings, memories (key-value facts the AI can read and edit), custom instructions | User and AI | Device, `Documents/settings.json` (secrets removed). Memories are added to prompts for some providers | Personalization | Until changed or deleted | `Managers/SettingsManager.swift`, `Models/AppSettings.swift` (line ~377), `Services/GeminiLive/GeminiLiveService.swift`, `Services/OpenAIRealtime/OpenAIRealtimeService.swift` |
| API keys, relay token, OAuth tokens | User enters or signs in | Device Keychain. API keys: `AfterFirstUnlock` (travel with encrypted backups). OAuth tokens: this-device-only | Authenticate to services the user chose | Until removed | `Managers/SettingsSecrets.swift`, `Services/OAuth/OAuthTokenStore.swift` |
| Accessibility suite data: routines, person reminders, activity trail, task guide state | User | Device, sealed | Accessibility features | Until deleted | `Services/Accessibility/AccessibilityCoordinator.swift` (~62-65, 534) |
| Workshop data: medication dose log, allergen watch list, place notes, journal, tallies, standing orders, skills | User | Device, sealed. The dose log is "never sent to an assistant" per code comment | Personal tools | Until "Erase everything the workshop keeps" | `Services/Workshop/*`, `Services/Workshop/Core/DoseGuard.swift`, `Core/IngredientWatch.swift`, `Views/Settings/WorkshopSettingsView.swift` (~150) |
| Documents the user imports | User | Device, `Documents/` | Ask questions about a document | Until removed | `Services/Documents/DocumentStore.swift` |
| Location | iPhone GPS (CoreLocation) | Device, plus Apple Maps / Apple geocoder | "Where am I", walking directions (background while walking), arrival reminders (region monitoring), notes tagged with place | Not stored, except a place label on notes and the geofence of a reminder the user set | `Services/Accessibility/WalkingGuide.swift`, `Services/Brain/Companion.swift` (`PlaceReminders`, ~679-720), `Services/NativeTools/ContextualNoteTool.swift`, `Services/Brain/PhoenixFoxFeatures.swift` (~194-206) |
| Contacts | Contacts (only a looked-up entry) | Device | Find a number or email when the user asks to call, text, or email; emergency contact | Not stored except the chosen emergency contact | `Services/Brain/Companion.swift`, `Services/Brain/PhoenixFoxFeatures.swift`, `Services/Brain/SmartCapture.swift` |
| Calendar and reminders | EventKit | Device. Event details can be returned to the AI model as a tool result when the user asks about the calendar | Read and add events and reminders on request | Not copied | `Services/NativeTools/CalendarTool.swift`, `ReminderTool.swift` |
| Photos | Photos library | Device | Save a glasses photo or recording; use a photo the user picks | In the user's Photos | `Services/Brain/SmartCapture.swift`, `Services/Recording/SessionRecorder.swift` |
| Session recordings (video + audio) | Glasses video + phone mic | Device, saved to Photos | Demo clips the user starts | In the user's Photos | `Services/Recording/SessionRecorder.swift` |
| Music control | Apple Music player | Device | Play, pause, skip | None | `Services/Brain/PhoenixFoxFeatures.swift` |
| Clipboard | Writes text | Device | Copy an answer | None | `Services/NativeTools/ClipboardTool.swift` |
| Glasses motion / worn state | DAT motion and don state | Device | Head gestures, posture (branch) | Not saved | `Services/Glasses/GestureMap.swift`; branch `cursor/meta-wearables-faq-df33`: `Services/Glasses/PresenceContext.swift`, `Core/WornPosture.swift` |
| Subscription status | StoreKit 2 (signed by Apple, verified on device) | Device (`UserDefaults` key `store.plan`) | Unlock paid plans | Until changed | `Services/Store/SubscriptionStore.swift` |
| Debug logs | `print` / `NSLog` | Device unified log only. **Some lines include what the user said** (see gaps) | Debugging | Per iOS log rotation | e.g. `Services/Voice/VoiceCommandService.swift:575`, `Services/AIBackend/CloudChat.swift:140`, `Services/GemmaLocal/GemmaLocalService.swift:745` |
| On-device models (Gemma, Qwen, SmolVLM, Bonsai, Kokoro, Whisper) | Downloaded from Hugging Face | Device | Offline AI and voice | Until the user deletes them | `Services/GemmaLocal/*`, `Services/TTS/KokoroTTSService.swift` |

## Data that leaves the phone

| Data | Recipient | When | Purpose | Retention | Linked | Code |
|---|---|---|---|---|---|---|
| Prompt text, recent conversation turns, custom instructions, memories (some providers), tool results (e.g. calendar events, note text, web results), **camera images** when the user asks to look | The AI provider the user selects: **xAI** (`api.x.ai`, default), **OpenAI** (`api.openai.com`, incl. Realtime WebSocket), **Anthropic** (`api.anthropic.com`), **Google Gemini** (`generativelanguage.googleapis.com`, incl. Live WebSocket) | Each request, only when that provider is configured and selected (or in the fallback order grok → anthropic → openai → on-device) | Answer the user | Set by the provider's terms under the user's own account or key | Yes, to the user's provider account or key | `Services/Brain/Providers/*`, `Services/AIBackend/*`, `Resources/model_catalog.json` |
| Continuous live audio and video frames | OpenAI Realtime or Gemini Live | Only in live mode with that provider | Real-time conversation | Provider terms | Yes | `Services/OpenAIRealtime/OpenAIRealtimeService.swift`, `Services/GeminiLive/*` |
| Guide mode scene frames (for a blind or low-vision user) | The configured cloud AI, when no on-device model can describe the scene | Guide mode with "cloud descriptions" on. **Default ON** (`AccessibilitySettings.swift` line 19), up to 60 calls per walk | Hazard and scene description | Provider terms | Yes | `Services/Accessibility/GuideMode.swift` (~125-185) |
| Assistant reply text | xAI or OpenAI text-to-speech | When the user picks a cloud voice | Spoken voice | Provider terms | Yes | `Services/TTS/CloudTTSService.swift`, `NeuralSpeech.swift` |
| OAuth sign-in (ChatGPT subscription, SuperGrok, Hermes dashboard) | OpenAI (`auth.openai.com`, `chatgpt.com/backend-api`), xAI (`auth.x.ai`), the user's Hermes server | When the user chooses subscription sign-in | Use the user's own subscription | Tokens on device | Yes | `Services/OAuth/*`, `Services/AIBackend/ChatGPTSubscription.swift`, `GrokService.swift`, `HermesGateway.swift` |
| Search queries | Tavily (`api.tavily.com`, user key) or DuckDuckGo (`html.duckduckgo.com`, `api.duckduckgo.com`, no key) | When the AI runs a web search | Live answers | Service terms | Tavily: yes (key). DuckDuckGo: IP only | `Services/Web/WebSearchService.swift` |
| Asks: text, transcript, recent context, up to ~780 KB of camera images, intent, target assistant name | A **relay** (Cloudflare Worker) at the address the user enters. Empty address = the developer's personal relay, which needs the owner's token, so other users cannot use it | When "your own assistant" is set up | Reach the user's own AI assistants (bots) | Asks: 15 min. Inbox messages: 24 h. Swept on each request. Then deleted | Yes, to the relay token | `Services/Relay/RelayClient.swift`, `relay/src/handle.ts` (`ASK_TTL_MS`, `INBOX_TTL_MS`, `sweep`) |
| Asks forwarded with webhooks | The bots named in the relay's `BOT_WEBHOOKS` secret (third-party services the relay operator chose) | When a webhook is configured | Deliver the ask | Recipient's policy | Yes | `relay/src/webhooks.ts`, `relay/src/handle.ts` (`sendAsk`) |
| APNs device token, platform, push environment | The relay, then **Apple Push Notification service** | When the user allows notifications and uses a relay | Tell the user a task is done | Until Apple reports the token invalid; max 8 devices kept | Yes (device token) | `Services/Relay/PushRegistration.swift`, `PushAlerts.swift`, `relay/src/handle.ts` (`postDevice`, `MAX_DEVICES`), `relay/src/apns.ts` |
| Push text (assistant name + message) | Apple APNs | Urgent pushes are visible alerts; others are silent | Notifications | Apple's terms | Device token | `relay/src/apns.ts` |
| Relay request metadata | **Cloudflare** (Workers Logs and traces enabled) | Every relay request | Operating and debugging the Worker | Per Cloudflare's log retention for the account | IP address | `relay/wrangler.toml` (`[observability]`) |
| SDK telemetry: app bundle ID, app version, SDK version, phone model and OS, **glasses device identifier**, firmware, registration, permission and session events, errors and crash hashes | **Meta** | Whenever the DAT SDK runs. **Opt-out key is not set**, so this is ON | Meta's SDK reliability and product improvement | Meta's terms | Device identifiers | Absence of `MWDAT > Analytics > OptOut` in `Resources/Info.plist`; Meta docs: https://wearables.developer.meta.com/docs/develop/dat/telemetry/ |
| Glasses registration and permissions | Meta AI app (on device), Meta | Pairing, and camera/mic permission per app | Required by Meta | Meta's terms | Meta account | `Services/Glasses/Core/GlassesRegistration.swift`, `Info.plist` `MWDAT` |
| Speech audio | Apple speech servers | Only when on-device recognition is unavailable or switched off | Transcription | Apple's terms | Per Apple's terms | `Services/Voice/VoiceCommandService.swift` |
| Location coordinates / search text | Apple Maps, Apple geocoder | Directions, "where am I" | Navigation | Apple's terms | Apple's terms | `WalkingGuide.swift`, `PhoenixFoxFeatures.swift` |
| IP address and model ID | Hugging Face | Model downloads | Get on-device models | HF terms | IP | `Services/GemmaLocal/LocalModelHub.swift`, `KokoroTTSService.swift` |
| Runtime metrics (latency, memory, CPU, a device name the user types) | The user's **own InfluxDB** | Only if the user enables telemetry and enters a URL (off by default) | Self-monitoring | The user's server | User's own | `Services/Telemetry/*`, `Models/AppSettings.swift` (~340-353) |
| Messages to the user's self-hosted gateways | OpenClaw or Hermes server the user enters | When configured | Use the user's own agent | The user's server | User's own | `Services/OpenClaw/*`, `Services/AIBackend/Hermes*` |
| Purchases | Apple (StoreKit) | Buying a plan (store builds only; selling is off today) | Subscriptions | Apple | Apple ID (Apple only). The app sends no purchase data to the developer | `Services/Store/SubscriptionStore.swift` |
| Call, text, email, WhatsApp hand-off | iOS Phone / Messages / Mail / WhatsApp | The user confirms, and iOS shows the composer; the user taps send | Communication | That app | — | `Services/Brain/PhoenixFoxFeatures.swift`, `Info.plist` `LSApplicationQueriesSchemes` |

## What the developer receives

For the public app: **nothing directly**. No analytics SDK, no crash SDK, no ad SDK, no account server. The developer receives only what Apple gives every developer (App Store Connect sales reports, and crash reports from users who opted in to share with developers), what Meta's developer console shows from DAT telemetry, and, for TestFlight testers, the tester's name and email plus any feedback they submit through TestFlight.

The relay at `phoenix-fox-relay.cinderandcrown.workers.dev` and its webhooks belong to the developer's own personal use (his own assistants). It is not a service offered to other users today.

## Open branches checked (14 Nov 2026)

- `cursor/meta-wearables-faq-df33`: adds `PresenceContext`, `WornPosture` (worn state and head pitch from glasses motion), `CompanionCard`, `InboxWalkGestures`. All on device. No new recipient.
- `cursor/engineering-standard-conformance-df33`: adds `WearableSessionPhase`, tests, scripts, and `Package.resolved`. No new data flow.
- `cursor/relay-webhook-signing-df33`: signs every webhook and can embed relay auth for body-only receivers. Same data, same recipients.
- `cursor/beta-feedback-diagnostics-df33` (WIP, not in the brief but found): **new flow.** A beta feedback report (note, transcript, source, app version, build, client-redacted diagnostics) is posted to the relay's new `/feedback` route and **kept 30 days** (`FEEDBACK_TTL_MS`). The policy has a clause for it, marked "beta builds".

## Gaps found in code

See `REVIEW_CHECKLIST.md` for the full list with status. The main ones:

1. **There is face recognition.** It is on-device and consent-gated, but it creates biometric identifiers (Texas CUBI, Illinois BIPA, Washington, GDPR Article 9). There is no written retention schedule or automatic expiry, and consent is the wearer's spoken "yes" on the other person's behalf, not a written release from that person.
2. No consent screen before personal data goes to a third-party AI (Apple guideline 5.1.2(i)).
3. Guide mode cloud descriptions default ON.
4. `PrivacyInfo.xcprivacy` declares no collected data, but Meta DAT telemetry is on, and the manifest is missing the System Boot Time required-reason API (`ProcessInfo.systemUptime`).
5. No privacy policy URL (`Services/Store/Core/StoreCatalog.swift` line 51 is `nil`), no privacy or licenses link in Settings, and Terms points to Apple's standard EULA.
6. Transcripts and prompts are written to the device log with `print`/`NSLog`.
7. Conversation history is stored as plain JSON in `Documents/` (backed up), unlike the sealed accessibility data.
8. `NSAllowsArbitraryLoads = true` in `Info.plist`.
