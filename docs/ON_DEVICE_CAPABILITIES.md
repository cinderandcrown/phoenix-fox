# On-device first

Phoenix Fox defaults every capability to the phone’s Neural Engine and the glasses’ own hardware. The cloud is used only when on-device quality is clearly worse, or the task needs deep reasoning, rich vision Q&A, or a bot action on the relay.

The same rows live in code as `CapabilityMatrix` (`OpenVision/Services/Brain/Core/OfflineCapability.swift`) so the app, this document, and the tests stay aligned.

**Why this matters for presence:** proactive nudges and shared context must be *cheap and local* so Phoenix can stay with the wearer without burning credits or waiting on the network. See [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md).

Cloud chat brains are provider-agnostic (`AIProvider` + `model_catalog.json`). **Grok is the default**; Claude, OpenAI, and Gemini swap without app-logic changes. The relay bots are not a model provider.

## Principle

> Default every capability to on-device. Use the cloud only when on-device quality is clearly worse, or the task needs it.

### Presence checklist (on-device features)

- [ ] Trigger for any proactive line is on-device (time, place, motion, frame change, worn, sound).
- [ ] Quiet period + Settings switch; Interrupt path consulted before speaking.
- [ ] Follow-ups reuse last on-device result when the scene is unchanged.
- [ ] Cloud is a fallback for richer language, not the alarm clock.
- [ ] Full checklist: [DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md#presence-checklist-every-feature).

**Offline mode** (no path to the internet) is shown on the home screen. Wake word, STT, TTS, OCR, scene labels, sound alerts, timers, notes, and local memory keep working. Bot actions and deep cloud reasoning refuse with a clear spoken line.

## Capability matrix

| Capability | Place | Offline | Uses (APIs actually called) | Cloud when |
| --- | --- | --- | --- | --- |
| Wake word | On-device | Yes | `SFSpeechRecognizer` (on-device when preferred) | Never for wake |
| Speech to text | On-device | Yes | `SFSpeechRecognizer`; WhisperKit after wake for assistants | Never a paid STT API |
| Text to speech | Either | Yes | `AVSpeechSynthesizer`; optional Kokoro / cloud voices | Only if chosen in Settings |
| Read aloud / OCR | On-device | Yes | Vision `VNRecognizeTextRequest` | Never for plain reading |
| Object / scene ID | Either | Yes | Vision classify / humans / animals | Rich vision Q&A when labels are not enough |
| Face detect / remember | On-device | Yes | Vision face prints on this phone | Never |
| Barcode / QR | On-device | Yes | Vision `VNDetectBarcodesRequest` | Never |
| Sound alerts | On-device | Yes | `SoundAnalysis` | Never |
| Short local replies | Either | Yes | Apple Intelligence Foundation Models when available | When unavailable and a key is set |
| Timers / notes | On-device | Yes | On-phone timers and notes | Never required |
| Local memory | On-device | Yes | Mind meld on this phone | Never without asking |
| Glasses mic | On-device | Yes | Bluetooth **HFP** (mono **16 kHz**) | Never |
| Glasses speakers | On-device | Yes | HFP for conversation, **A2DP** for long playback — **not both at once** | Never |
| Glasses camera | On-device | Yes | DAT camera stream; capture light is hardware | Frames leave only for a look that needs rich vision |
| Deep reasoning | Cloud | No | Grok / Claude / OpenAI top model | When the turn needs the top model |
| Rich vision Q&A | Either | Partial | On-device SmolVLM2 when loaded; else cloud | When no local VLM and OCR/labels are not enough |
| Bot team actions | Cloud | No | Relay `/ask` | Always needs the relay |

## Glasses audio and camera (DAT 1.0.1)

Verified against Meta’s DAT README (“photo capture … experimental; unavailable for production publishing”), the 1.0.1 camera interface (`PhotoResolution`, `AudioSampleRate.rate16000`, raw vs compressed stream), and this repo’s `docs/GLASSES_SDK.md`:

1. **HFP and A2DP cannot run simultaneously.** The audio session picks one link mode: `hfpConversation` (mic + short replies) or `a2dpPlayback` (speaker only). Category options never enable both at once.
2. **HFP must settle before the camera stream starts**, or glasses audio can fail with no error. `AudioSessionManager.waitUntilCameraSafe()` runs before `startStreaming`.
3. **Glasses mic on HFP is mono 16 kHz**, tuned to the wearer.
4. **Raw frames arrive only while the app is foregrounded.** Background gets HEVC that DAT does not decode. Looks while locked are refused with a spoken line. We do **not** promise background vision.
5. **Full-sensor photo capture is experimental** and Meta says apps using it cannot ship to the App Store yet. Store / standard builds use stream frames. Owner / TestFlight builds may enable whole-sensor photos under Glasses limits.

## Pre-filter before a cloud look

1. If the request is “read this” / “what does this say” → OCR on-device; send text, not the image, when OCR is enough.
2. If the request is a barcode → on-device barcodes first.
3. If the scene has not changed (`FrameChange`) → skip the model call.
4. Else try on-device scene labels / local VLM; cloud vision only when still needed and online.

## Unverified on hardware

Until run on Adventurer glasses with a TestFlight build:

- HFP settle timing (0.7 s) under real radio conditions.
- A2DP long-playback quality vs HFP for short replies on Adventurer.
- Whether DAT PCM while the camera streams is usable for STT (wired as optional; not claimed as primary STT).
- Foundation Models availability on every owner device.
