# SDK notes — Meta Wearables DAT 1.0.1

**Pinned package:** `https://github.com/meta/meta-wearables-dat-ios` exact `1.0.1`  
**Resolved revision:** `0bd369298eef6a980ad0bdb6c8a5502f2c02a08c` (see `Package.resolved`)  
**Canonical URL:** `github.com/meta/meta-wearables-dat-ios`. `github.com/facebook/meta-wearables-dat-ios` 301-redirects to the same repo and the same tag SHA. This project uses the `meta/` URL.  
**License:** Meta Wearables Developer Terms — **do not commit** SDK binaries or official skills. Sync with `bash scripts/setup_mac.sh` (gitignored under `.vendor/` and `.agents/skills/meta-official-*/`).  
**Citation basis:** arm64-apple-ios `.swiftinterface` files inside the 1.0.1 xcframeworks (not guessed). Paths below are relative to each module’s `…/Modules/<Module>.swiftmodule/arm64-apple-ios.swiftinterface`.

Simulator and unit-test results are **never** glasses hardware results.

---

## Experimental / non-publishable (CHANGELOG 1.0.1)

Apps that depend on these **cannot be published** yet (CHANGELOG: “features labeled experimental… cannot be published yet”). Each is gated by `GlassesCapabilitySettings` + `BuildFlavor.allowsExperimental` (owner build only), with a fallback.

| Capability | Gate | Fallback when off / non-owner |
|---|---|---|
| `MWDATInputs` (touchpad, capture/action button, Neural Band) | `controls` / `captureButton` | Phone UI / wake word only |
| `MWDATMotion` (head nod/shake) | `headGestures` | Spoken yes/no |
| `MWDATSpeech` (on-glasses STT) | `onGlassesSpeech` | Phone mic + SFSpeech |
| `VoiceInvocationsStream` / `LaunchApp` | Always attempted when SDK runs; experimental per CHANGELOG | Phone open / deep link |
| `Camera.photo` high-res stills | `highResolutionStills` | Stream frame JPEG via `stream.capturePhoto` |
| `StreamConfiguration.audioCodec` ambient audio | `ambientAudio` | Phone mic / no glasses ambient |

`fullRateVideo` is not labeled experimental in CHANGELOG; it remains available in standard builds when set.

---

## API inventory (every MWDAT* symbol the app uses)

### MWDATCore

| App use | Signature | SDK citation (1.0.1) |
|---|---|---|
| `Wearables.configure()` | `static func configure() throws(WearablesError)` | MWDATCore.swiftinterface:649 |
| `Wearables.shared` | `static var shared: any WearablesInterface` | :650 |
| `WearablesInterface` | protocol | :627 |
| `startRegistration()` | `func startRegistration() async throws(RegistrationError)` | :631 |
| `startUnregistration()` | `func startUnregistration() async throws(UnregistrationError)` | :634 |
| `handleUrl(_:onRegistrationRequest:)` | async throws → `Bool` | :633 |
| `RegistrationRequest` | class; `continueRegistration()` / `cancelRegistration()` | :254–258 |
| `RegistrationState` | `.unavailable` `.available` `.registering` `.registered` | :182–185 |
| `addRegistrationStateListener` | on `WearablesInterface` | :629 |
| `registrationState` | property | :628 |
| `devices` | `[DeviceIdentifier]` | :637 |
| `devicesStream()` | `AsyncStream<[DeviceIdentifier]>` | :639 / :656 |
| `checkPermissionStatus` / `requestPermission` | `Permission` → `PermissionStatus` | :641–642 |
| `Permission` | `.camera` `.microphone` | :137–138 |
| `PermissionStatus` | `.granted` `.denied` | :150–152 |
| `createSession(deviceSelector:)` | → `DeviceSession` | :643 |
| `SpecificDeviceSelector` / `AutoDeviceSelector` | `DeviceSelector` | :337–346 |
| `DeviceSession` | class | (DeviceSession region ~:350+) |
| `DeviceSession.statePublisher` | `Announcer<DeviceSessionState>` | :356 |
| `DeviceSession.start()` | `throws(DeviceSessionError)` | :369 |
| `DeviceSessionError` | enum | :374 |
| `DeviceSessionState` | `.idle` `.starting` `.started` `.paused` `.stopping` `.stopped` | :398–403 |
| `DeviceState` | struct (battery, don, hinge, …) | :414 |
| `Device.addDeviceStateListener` | → `AnyListenerToken` | :325 |
| `Device.deviceType()` / `supportsDisplay()` | | :328–330 |
| `DeviceType.metaGlasses` / `supportsDisplay` | | :72 / :84 |
| `DeviceIdentifier` | `typealias String` | :64 |
| `Announcer.listen` | → `AnyListenerToken` | :117 |
| `VoiceInvocationsStream` | `init(wearables:)` / `start(deviceIdentifier:)` | :742–750 **EXPERIMENTAL** |
| `LaunchApp` | `struct LaunchApp: VoiceInvocation` | :713 **EXPERIMENTAL** |

**App files:** `WearablesSDK.swift`, `GlassesManager.swift`, `GlassesControlSession.swift`, `GlassesLink.swift`, `GlassesHUD.swift`, `GlassesProductTarget.swift`, `OpenVisionApp.swift`.

### MWDATCamera

| App use | Signature | SDK citation |
|---|---|---|
| `DeviceSession.addCamera(config:)` | → `Camera?` | MWDATCamera.swiftinterface:39 |
| `Camera.stream` / `Camera.photo` / `Camera.stop()` | | :16–17, :24 |
| `Stream.start()` / `stop()` | | :349–350 |
| `Stream.capturePhoto(format:)` | → `Bool` | :352 |
| `StreamConfiguration` init with codecs/resolution/frameRate | | :354–360 |
| `AudioCodec.pcm(...)` | **EXPERIMENTAL** audio streaming | :311–312 |
| `Photo.start/stop/capturePhoto(resolution:quality:)` | **EXPERIMENTAL** | :235–237 |
| `Photo.statePublisher` / `photoDataPublisher` / `errorPublisher` / `transferProgressPublisher` | | :222–231 |
| `PhotoCaptureData.imageData` | | :240 |
| `PhotoResolution` / `PhotoQuality` | | :261 / :276 |

**App files:** `GlassesManager.swift` (stream + gated photo path).

### MWDATDisplay

| App use | Signature | SDK citation |
|---|---|---|
| `DeviceSession.addDisplay()` | → `Display` | MWDATDisplay.swiftinterface:13 |
| `Display.start/stop/send(_:)/clearDisplay()` | | :38–41 |

**App files:** `GlassesHUD.swift` — gated on `supportsDisplay`; no-op on displayless Adventurer.

### MWDATInputs (**EXPERIMENTAL**)

| App use | Signature | SDK citation |
|---|---|---|
| `addInputs(configuration:)` / `removeInputs()` | | MWDATInputs.swiftinterface:12–13 |
| `InputsConfiguration(sources:)` | | :44–47 |
| `Inputs.events` | `AsyncStream<InputEvent>` | :37 |
| `InputSource` cases used | captouch, captureButton, actionButton, neuralBand, … | :90–95 |

**App files:** `GlassesControlSession.swift` behind `controls` / `captureButton`.

### MWDATMotion (**EXPERIMENTAL**)

| App use | Signature | SDK citation |
|---|---|---|
| `addMotion(configuration:)` / `removeMotion()` | | MWDATMotion.swiftinterface:13–14 |
| `MotionConfiguration(samplingRate:)` | | :29–31 |
| `Motion.start/stop` / `samples` | | :71–77 |

**App files:** `GlassesControlSession.swift` behind `headGestures`.

### MWDATSpeech (**EXPERIMENTAL**)

| App use | Signature | SDK citation |
|---|---|---|
| `addSpeech()` / `removeSpeech()` | | MWDATSpeech.swiftinterface:12–13 |
| `Speech.start/stop` | | :134–135 |
| `transcriptionPublisher` / `statePublisher` / `errorPublisher` | | :116–122 |

**App files:** `GlassesControlSession.swift` behind `onGlassesSpeech` + mic permission.

### MWDATMockDevice

| App use | Signature | SDK citation |
|---|---|---|
| `MockDeviceKit.shared` / `enable()` | | MWDATMockDevice.swiftinterface:98–99, :94 |

**App files:** referenced for future Mock Device Kit tests; live usage in FAQ / meta-faq branch work. **No scenario below claims Mock Device Kit pass on this Linux agent.**

---

## Flags / not found

| Item | Status |
|---|---|
| Invented `MetaGlassesManager` API | **Not used** (forbidden by SKILL) |
| `facebook/` package URL | **Fixed** → `meta/` |
| Official skills on tag `1.0.1` | **Absent** on tag; present on `main` `plugins/mwdat-ios/skills/` — synced by `setup_mac.sh`, not committed |
| Redistributing SDK/skills in git | **Disallowed** by Developer Terms |

---

## Acceptance scenarios (`docs/CAPABILITIES.md`)

| # | Scenario | Verification |
|---|---|---|
| 1 | Clean install / onboarding | **Unit:** `CapabilitiesAcceptanceTests.testScenario1_*` |
| 2 | Connect / register status | **Unit:** `testScenario2_*` (+ `GlassesRegistrationTests`) |
| 3 | Deny permission path | **Unit:** `testScenario3_*` |
| 4 | Start/stop camera session path | **Unit:** `testScenario4_*` (state machine). **UNVERIFIED on glasses** |
| 5 | AI action / no surprise stream | **Unit:** `testScenario5_*` (SDK-absent host) |
| 6 | Disconnect mid-flight | **Unit:** `testScenario6_*` (phase). **UNVERIFIED on glasses** |
| 7 | Interruption | **Unit:** `testScenario7_*` |
| 8 | Displayless fallback | **Unit:** `testScenario8_*` |
| 9 | Display glasses HUD | **UNVERIFIED** — needs Display hardware or DisplayAccess sample (`testScenario9_*` XCTSkip) |
| 10 | Release gate / experimental strip | **Unit:** `testScenario10_*` + docs |

---

## Session state machine

Pure Swift: `WearableSessionPhase` / `WearableSessionMachine` in `OpenVision/Services/Glasses/Core/WearableSessionPhase.swift`. DAT `DeviceSessionState` remains inside the adapter (`GlassesManager` / `GlassesControlSession`). Every phase exposes `nextAction`.
