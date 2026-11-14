# Google Play Data safety answers (future Android app)

> **Draft prepared for review; have a licensed attorney review before publishing.**

## Summary

- There's **no Android app yet**. These answers assume the Android version has the same features and data flows as the iPhone app (see [DATA_INVENTORY.md](DATA_INVENTORY.md)), using Meta's Wearables Device Access Toolkit for Android.
- Declare **voice, photos and videos, other user content, and in-app search history** as **collected** (sent to the AI or search service the user picks), **not shared**, **not used for ads**, and **optional**.
- **Meta's toolkit telemetry is turned off** (decided 14 Nov 2026) with the Android manifest opt-out, so no device IDs or diagnostics are declared.
- **Cloud AI uses pasted API keys only.** No ChatGPT-subscription or SuperGrok sign-in in Play builds.
- The Android design should avoid **background location**, `SEND_SMS`, and `CALL_PHONE`, so it doesn't need restricted-permission declarations.
- Play requires an **in-app way to report offensive AI output**, and a privacy policy link in the app and the listing. An account-deletion URL isn't required while there are no accounts.

Re-check every answer against the real Android code before submitting.

---

## 1. Play's definitions, applied

- **Collected:** data transmitted off the device by the app or its SDKs. On-device processing isn't collected.
- **Shared:** data transferred to a third party. Play's exceptions include transfers that are **user-initiated**, where the user reasonably expects the data to go to that third party (Play Console Help, "Provide information for Google Play's Data safety section"). Sending a prompt to the AI provider the user chose and connected with their own key fits that exception, so it's declared **collected, not shared**. If counsel disagrees, mark the same rows "shared" too. Over-declaring is safer than under-declaring.
- **Processed ephemerally:** kept in memory only, for the request. AI providers may keep requests (for example, for abuse monitoring), so answer **No**.

## 2. Overview questions

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes.** HTTPS/WSS to providers. Make sure the Android network security config doesn't allow cleartext, except for user-entered LAN addresses |
| Do you provide a way for users to request that their data is deleted? | **Yes.** In-app delete controls, uninstalling, and email to the contact address. Data at an AI provider is deleted with that provider's controls |
| Has your app undergone an independent security review (MASA)? | No (optional) |

## 3. Data types (Meta telemetry off, API keys only)

| Play category > type | Collected | Shared | Ephemeral | Required or optional | Purposes | Source in iOS code |
|---|---|---|---|---|---|---|
| Audio > **Voice or sound recordings** | Yes | No | No | Optional | App functionality | Live mode streaming (OpenAI Realtime, Gemini Live) |
| Photos and videos > **Photos** | Yes | No | No | Optional | App functionality | Camera frames to the chosen AI ("look", Guide cloud descriptions) |
| Photos and videos > **Videos** | Yes | No | No | Optional | App functionality | Live-mode video frames |
| App activity > **Other user-generated content** | Yes | No | No | Optional | App functionality | Prompts and transcripts, conversation context, memories, instructions, notes and calendar tool results, reply text for cloud voices |
| App activity > **In-app search history** | Yes | No | No | Optional | App functionality | Web search queries to DuckDuckGo or Tavily |
| Messages > Other in-app messages | **Consider Yes** | No | No | Optional | App functionality | Only if the Android app relays messages to the user's own assistants through a relay. In the public app the relay is the user's own. Declare it if Cinder and Crown runs a relay |
| Location > Approximate / Precise | **No**, *if* location stays on device. **Yes, ephemeral, optional, App functionality** if Android sends coordinates to a geocoding or directions web service | No | — | Optional | App functionality | iOS uses Apple MapKit. Decide when Android picks a maps provider |
| Personal info (name, email, IDs, address, phone, etc.) | No | | | | | No accounts |
| Financial info | No | | | | | Google Play Billing is Google's |
| Health and fitness | No | | | | | Medication log stays on device |
| Contacts | No | | | | | Single on-device lookups, handed to the dialer or messaging intents |
| Calendar | No | | | | | On device. Event text can go to the AI only as user content (covered above) |
| Files and docs | No | | | | | Imported documents stay on device, unless the user asks about one, and then the excerpt is user content |
| Web browsing | No | | | | | |
| App info and performance | No | | | | | No crash or analytics SDK |
| Device or other IDs | No | | | | | No ad ID |
| Biometric (face prints) | Not a Play category. **Not collected** (on device only). Disclose in the privacy policy | | | | | `AccessFaces.swift` |

**Meta telemetry is off (decided).** Put this in `AndroidManifest.xml`, inside `<application>`. If it were ever removed, you'd have to add *Device or other IDs* and *App info and performance > Crash logs, Diagnostics* as collected and shared with Meta:

```xml
<meta-data
    android:name="com.meta.wearable.mwdat.ANALYTICS_OPT_OUT"
    android:value="true" />
```

(Source: https://wearables.developer.meta.com/docs/develop/dat/telemetry/)

## 4. Play policy requirements for this app

### 4.1 Privacy policy

- Enter the public privacy policy URL in **Play Console > App content > Privacy policy**, and link it inside the app (User Data policy).
- **Prominent disclosure and consent** (User Data policy): before sending personal or sensitive data that users wouldn't expect, such as camera images and voice sent to a third-party AI, show an in-app disclosure that says what is sent and to whom, and get affirmative consent. The iOS consent screen copy in [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md), section C, works for both.

### 4.2 Camera and microphone

- `CAMERA` and `RECORD_AUDIO` are runtime permissions. Request them in context, only when the feature is first used.
- Android 14+ requires **foreground service types** for work that keeps running: `microphone` (wake word, captions), `camera` (if the phone camera is used), `connectedDevice` (glasses over Bluetooth), and `location` (walking guide). Each needs its `FOREGROUND_SERVICE_*` permission and the **Foreground service permissions declaration** in Play Console, which may need a video.
- Android shows mic and camera indicators. Don't try to hide them. The glasses' own capture light stays under Meta's control.
- Bluetooth: `BLUETOOTH_CONNECT`, and `BLUETOOTH_SCAN` with `neverForLocation` if scanning isn't used to derive location.

### 4.3 Location, especially background location

- **Avoid `ACCESS_BACKGROUND_LOCATION`.** Turn-by-turn walking directions can run as a foreground service with type `location`, started by the user, which needs only foreground location.
- Arrival reminders (geofences) **need background location** on Android. If they're kept, Play requires: the **Location permissions declaration** form, a short video, background location being core to the app, and a **prominent in-app disclosure** shown *before* the runtime prompt, using wording like "Phoenix Fox collects location data to remind you when you arrive at a place you named, even when the app is closed or not in use." **Recommendation:** leave arrival reminders out of Android v1.

### 4.4 Contacts, calls, and SMS

- `READ_CONTACTS` is fine for "call or text [name]", with a prominent disclosure.
- **Don't request `SEND_SMS`, `READ_SMS`, or the call log** (restricted SMS/Call Log permissions). Use `ACTION_SENDTO` and `ACTION_DIAL` intents so the user sends or calls from the system app, matching the iOS behavior where the user taps send.
- Prefer `ACTION_DIAL` over `ACTION_CALL` (which needs `CALL_PHONE`), even for the emergency contact.

### 4.5 Photos and videos

- The **Photo and Video Permissions** policy limits `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` to apps whose core purpose needs broad access. Use the **Android photo picker** for "use a photo from my library", and `MediaStore` writes (no read permission) to save glasses photos.

### 4.6 AI-Generated Content policy

Phoenix Fox generates AI text and speech, so Play's AI-Generated Content policy applies:

- Provide an **in-app way to report or flag offensive AI output** without leaving the app (for example, "Report this answer" on each reply in History, plus a spoken command "report that answer"). Use the reports to improve safeguards. **This doesn't exist yet. Needs a code change.**
- Don't let the app generate prohibited content (child sexual abuse material, content that facilitates deception, and so on), and rely on provider safety systems plus prompt safeguards.
- Since the user picks third-party models, the store listing must describe AI features accurately.

### 4.7 Accessibility API

If the Android app uses `AccessibilityService`, it must follow Play's Accessibility API policy (disclosure and consent, and `isAccessibilityTool` only for genuine assistive tools). The current feature set (camera reading, captions, sound alerts) **doesn't need** `AccessibilityService`. Avoid it.

### 4.8 Health features

The medication log and allergen check are health-adjacent. Complete Play Console's **Health apps declaration** accurately (Play Console > App content), and keep the "not a medical device" disclaimer in the app and listing. Don't use Health Connect unless it's needed.

### 4.9 Account deletion URL

Play requires an in-app and web account-deletion path **only if the app lets users create an account**. Phoenix Fox has no accounts. Cloud AI uses API keys the user pastes (no ChatGPT-subscription or SuperGrok sign-in in store builds). A self-hosted Hermes sign-in is to the user's own server, not a Phoenix Fox account. **Not required now.** If Phoenix Fox accounts are added (for example "Included AI"), add the in-app path and a web URL such as `[PRIVACY POLICY URL]#delete-your-data` in **App content > Data safety > Data deletion**.

### 4.10 Target audience and content rating

Set the target audience to **18+ only**, and complete the IARC content-rating questionnaire, answering yes to user-generated and AI-generated content where asked. That keeps the app out of the Families program.

### 4.11 Meta's terms

The Android toolkit is covered by the same Meta Wearables Developer Terms. Don't use "Meta", "Ray-Ban", or "Oakley" in the Play title or icon.
