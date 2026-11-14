# App Store privacy answers and privacy manifest

> **Draft prepared for review; have a licensed attorney review before publishing.**

## Summary

- These are the answers for **App Store Connect > App Privacy**, derived from [DATA_INVENTORY.md](DATA_INVENTORY.md).
- Phoenix Fox has no account, analytics, ads, or tracking SDKs. The only data that leaves the phone goes to **AI and search services the user turns on**, using the user's own pasted API keys.
- **Decided (14 Nov 2026):** Meta's toolkit telemetry is **turned off**, and ChatGPT-subscription and SuperGrok sign-ins are **removed from store builds**. Use **Answer set A**. Set B is kept only for reference, in case the telemetry opt-out is ever reverted.
- Before submitting, the code must match: the Meta opt-out key, the AI consent screen, and no subscription sign-ins in store builds (REVIEW_CHECKLIST C1, C4, C12).
- The app already has `OpenVision/Resources/PrivacyInfo.xcprivacy`. It's missing the **System Boot Time** API reason, and its "collects nothing" claim doesn't match the code. A corrected draft is below. It hasn't been applied to the code.

---

## 1. Ground rules used

Apple's definitions (App Store Connect Help, "App privacy details on the App Store"):

- **Collect** means transmitting data off the device in a way that lets you and/or your third-party partners access it for longer than needed to service the request in real time.
- Data from **third-party SDKs and partners** counts, as if it were yours.
- **Tracking** means linking data from your app with other companies' data for targeted advertising or ad measurement, or sharing it with data brokers.
- Data processed only on the device isn't "collected".

How this applies to Phoenix Fox:

- **AI provider traffic** (xAI, OpenAI, Anthropic, Google) is sent off the device, and providers keep it longer than real time (for example, for abuse monitoring). It's sent at the user's request, under the user's own key or sign-in. **Conservative choice: declare it.** It's user-initiated and can be explained in the review notes, but Apple's 2025 change to guideline 5.1.2(i) singles out sharing with third-party AI, so under-declaring is the bigger risk.
- **Apple's own services** (server speech recognition, MapKit, APNs, StoreKit, iCloud Backup) are Apple's processing, under Apple's privacy policy. They aren't declared.
- **Relay traffic:** in the public app, a relay is one the user runs and enters. The developer's relay needs the owner's token and isn't a service for other users. **Not declared.** If Cinder and Crown ever runs a relay or "Included AI" for subscribers, add Identifiers > Device ID (push token) and the user-content types it carries.
- **Face prints, transcripts, the medication log, location, and contacts** never leave the phone. **Not declared.**

## 2. Answer set A (use this: Meta telemetry off, API keys only, consent screen shipped)

**Do you or your third-party partners collect data from this app?** Yes.

| Apple data type | Collected? | Purposes | Linked to the user? | Used for tracking? | Why |
|---|---|---|---|---|---|
| User Content > **Audio Data** | Yes | App Functionality | Yes | No | Live mode streams voice to OpenAI Realtime or Gemini Live (`Services/OpenAIRealtime`, `Services/GeminiLive`) |
| User Content > **Photos or Videos** | Yes | App Functionality | Yes | No | Camera frames sent to the chosen AI when the user asks it to look, and in Guide mode cloud descriptions |
| User Content > **Other User Content** | Yes | App Functionality | Yes | No | Prompts and transcripts as text, recent conversation, custom instructions, memories, tool results (notes, calendar events), and reply text for cloud voices |
| **Search History** | Yes | App Functionality | Yes (Tavily key). DuckDuckGo: no | No | Web search queries (`Services/Web/WebSearchService.swift`) |
| Contact Info | No | | | | No account, name, email, or phone collected |
| Health & Fitness | No | | | | Medication log stays on device (`Workshop/Core/DoseGuard.swift`) |
| Financial Info | No | | | | StoreKit is Apple's |
| Location (Precise / Coarse) | No | | | | CoreLocation is used on device and with Apple MapKit only. *Note: a note's place label can appear in a tool result sent to the AI. That's covered by Other User Content* |
| Sensitive Info | No | | | | Face prints are on-device only (`AccessFaces.swift`) |
| Contacts | No | | | | Single lookups on device, handed to iOS composers |
| Browsing History | No | | | | |
| Identifiers (User ID / Device ID) | No | | | | |
| Purchases | No | | | | The app sends no purchase data off device. Apple handles it |
| Usage Data | No | | | | |
| Diagnostics | No | | | | No crash or analytics SDK. Apple's opt-in crash sharing is Apple's |
| Surroundings / Body | No | | | | No environment mesh or hand/head tracking is sent |
| Other Data | No | | | | |

**"Linked to the user" reasoning:** the user's own API key identifies them to the provider. The developer has no account system. If counsel prefers, "Not linked" is arguable for the user's own-key traffic. "Linked" is the safer answer.

**Privacy policy URL:** [PUBLIC URL, see REVIEW_CHECKLIST.md item P1]
**User privacy choices URL (optional):** the same URL, section 11 anchor.

## 3. Answer set B (reference only. Not used, because Meta telemetry is turned off)

Only if the opt-out were reverted: everything in set A, plus:

| Apple data type | Collected? | Purposes | Linked? | Tracking? | Why |
|---|---|---|---|---|---|
| Identifiers > **Device ID** | Yes | Analytics, App Functionality | Yes | No | The glasses device identifier and app session UUID sent by the DAT SDK |
| Diagnostics > **Crash Data** | Yes | Analytics | Yes | No | DAT error reporting and crash grouping |
| Diagnostics > **Performance Data** | Yes | Analytics | Yes | No | Session durations, streaming events |
| Diagnostics > **Other Diagnostic Data** | Yes | Analytics | Yes | No | Phone model, OS, firmware, registration and permission events |

Source: https://wearables.developer.meta.com/docs/develop/dat/telemetry/. The opt-out key isn't present in `OpenVision/Resources/Info.plist`.

**Required code change (decided)**, inside the existing `MWDAT` dict in `OpenVision/Resources/Info.plist`:

```xml
<key>Analytics</key>
<dict>
    <key>OptOut</key>
    <true/>
</dict>
```

## 4. Privacy manifest (`PrivacyInfo.xcprivacy`)

### 4.1 What exists today

`OpenVision/Resources/PrivacyInfo.xcprivacy` declares:

- `NSPrivacyTracking` = false. **OK.**
- `NSPrivacyTrackingDomains` = empty. **OK.**
- `NSPrivacyCollectedDataTypes` = empty. **Inaccurate:** AI and search traffic (set A). Meta telemetry won't need declaring once the opt-out key ships.
- `NSPrivacyAccessedAPITypes`: UserDefaults `CA92.1` (OK) and File Timestamp `C617.1` (OK: `GemmaLocalService.swift` reads `creationDateKey` on its own temp files).

### 4.2 Gaps

| # | Gap | Evidence | Fix |
|---|---|---|---|
| M1 | **System Boot Time API not declared** | `ProcessInfo.processInfo.systemUptime` in `Managers/GlassesManager.swift`, `Services/Accessibility/SoundAlertService.swift`, `Services/Glasses/GlassesControlSession.swift`. The Meta `MWDATCore` binary also references `systemUptime` and `mach_absolute_time` | Add `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1` (measure time between events in the app) |
| M2 | Collected data types empty | See section 2 | Add the types from set A (and set B if telemetry stays on) |
| M3 | **The Meta DAT SDK ships no privacy manifest** | Its 1.0.1 xcframeworks contain no `PrivacyInfo.xcprivacy`. A strings scan of `MWDATCore` shows `NSUserDefaults`, `systemUptime`, `mach_absolute_time`, `stat`/`fstat` | The app manifest covers UserDefaults, File Timestamp, and System Boot Time, which also covers what the SDK appears to use. Ask Meta to ship a manifest |
| M4 | Third-party SPM packages | WhisperKit, FluidAudio, swift-transformers, swift-huggingface, mlx-swift, ZIPFoundation | After an archive, run **Xcode > Product > Archive > Generate Privacy Report**, and confirm every binary with required-reason APIs has a manifest. None of these is on Apple's list of commonly used SDKs that must be signed. Check for Disk Space (`volumeAvailableCapacity`) use in model downloaders. If found, add `NSPrivacyAccessedAPICategoryDiskSpace` with `E174.1` |

### 4.3 Corrected draft (set A, plus M1). Use this

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <!-- Sent only to the AI provider or search service the user turns on, with the user's own key. -->
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeAudioData</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypePhotosorVideos</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeOtherUserContent</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
        <dict>
            <key>NSPrivacyCollectedDataType</key>
            <string>NSPrivacyCollectedDataTypeSearchHistory</string>
            <key>NSPrivacyCollectedDataTypeLinked</key>
            <true/>
            <key>NSPrivacyCollectedDataTypeTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypePurposes</key>
            <array><string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string></array>
        </dict>
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>CA92.1</string></array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>C617.1</string></array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>35F9.1</string></array>
        </dict>
    </array>
</dict>
</plist>
```

Only if Meta telemetry were ever turned back on, add `NSPrivacyCollectedDataTypeDeviceID`, `NSPrivacyCollectedDataTypeCrashData`, `NSPrivacyCollectedDataTypePerformanceData`, and `NSPrivacyCollectedDataTypeOtherDiagnosticData`, each with purpose `NSPrivacyCollectedDataTypePurposeAnalytics`, linked true, and tracking false.

## 5. Purpose strings (Info.plist) review

Present and specific: microphone, camera, contacts, Apple Music, speech recognition, Bluetooth (always and peripheral), local network plus Bonjour, photo library (add and read), location (when in use, and always), calendars (legacy and full access), and reminders (legacy and full access). They're specific and accurate, which satisfies guideline 5.1.1(ii).

Issues to fix or explain:

1. `NSCameraUsageDescription` refers to the **glasses** camera. iOS shows this prompt only when the **phone** camera is used, and no `AVCaptureDevice` use was found in `OpenVision/`. Keep the key (harmless) or remove it. The glasses camera permission is granted in the Meta AI app.
2. **Location "Always"** (`NSLocationAlwaysAndWhenInUseUsageDescription`) plus the `location` background mode will draw review questions. The text is accurate (arrival reminders and turn-by-turn walking directions while locked). Explain both in the review notes, and show a demo.
3. **Background modes:** `audio` (wake word and spoken replies to the glasses), `bluetooth-central`, `bluetooth-peripheral` and `external-accessory` (required by Meta's toolkit), `location` (walking guide), `remote-notification` (relay pushes). Each needs a sentence in the review notes (guideline 2.5.4).
4. `NSAllowsArbitraryLoads = true` (ATS fully off) needs a justification, or should be narrowed. Self-hosted gateways and local InfluxDB on a LAN are covered by `NSAllowsLocalNetworking`. Prefer removing `NSAllowsArbitraryLoads`.
5. No `NSUserTrackingUsageDescription` is needed (no ATT, no IDFA).
