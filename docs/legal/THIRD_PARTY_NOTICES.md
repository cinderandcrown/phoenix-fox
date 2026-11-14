# Licenses and third-party components: audit

> **Draft prepared for review; have a licensed attorney review before publishing.**

## Summary

- **Our code is Apache-2.0** (root `LICENSE` and `NOTICE`). Every source file now has an SPDX header. Files that started in OpenVision say `Apache-2.0 AND MIT`, to keep the MIT notice honest.
- **Everything linked into the app is permissive** (MIT, Apache-2.0, BSD-2-Clause), except Meta's SDK, which is proprietary and used under Meta's terms.
- **Two problems to fix before a store release:**
  1. **FluidAudio floats** (`from: "0.15.5"`, and it resolves to **0.18.3**). Since v0.15.8 its default build bundles LuxTTS pronunciation data **derived from eSpeak NG (GPL-3.0-or-later)** and FrequencyWords (**CC-BY-SA-4.0**). We only use its voice-activity detector. **Fix:** pin `exactVersion: "0.15.5"`, or turn off FluidAudio's `TTS` package trait.
  2. **The Qwen2.5-3B-Instruct model** offered for download is under the **Qwen Research License (non-commercial)**. **Fix:** remove it from the paid app's model list, or replace it with an Apache-2.0 model.
- Also: **Gemma 2 2B** comes with Google's Gemma Terms of Use, whose use restrictions must be passed on to users. The app needs an **in-app Licenses screen** (MIT, BSD, and Apache all require the notices to travel with the binary).

The full license texts that ship with the source are in the root [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md). This file is the audit behind it.

---

## 1. Our own code

| Item | License | Notes |
|---|---|---|
| Phoenix Fox app (`OpenVision/`, `OpenVisionTests/`), relay (`relay/`), scripts (`scripts/`), docs | Apache-2.0, © 2026 Cinder and Crown LLC | Root `LICENSE` and `NOTICE`. `relay/package.json` and `package-lock.json` now say `"license": "Apache-2.0"` |
| `telemetry/` (Docker Compose and Grafana provisioning for a self-hosted dashboard) | Apache-2.0 (root LICENSE). The dashboard JSON came from OpenVision (MIT) | **No package manifest exists**, so there's no license field to add. It references the `influxdb:2.7` image (MIT) and `grafana/grafana:11.1.0` (**AGPL-3.0**). Those images aren't redistributed. Users pull them. Running unmodified Grafana for yourself creates no obligation. Not part of the app |
| Branding ("Phoenix Fox", logo) | Not licensed | `NOTICE` reserves the trademarks |

**SPDX headers (part b): chosen, because the repo already used per-file headers** (183 of 286 source files had `SPDX-License-Identifier: Apache-2.0`). This PR adds headers to the other 103:

- **98 files that exist in upstream OpenVision** (`// OpenVision - ...` headers, plus `MainTabView.swift`, the bridging header, and `OVExceptionCatcher.h/.m`) now start with `SPDX-License-Identifier: Apache-2.0 AND MIT` and a line naming OpenVision and its MIT copyright. Our changes to these files are under Apache-2.0, and the upstream MIT notice is preserved.
- **5 relay test and config files** got `Apache-2.0` with the Cinder and Crown copyright line.
- Three upstream-named files (`AudioSessionManager.swift`, `Theme.swift`, `VoiceAgentView.swift`) were already marked Apache-2.0 only. They were compared against upstream and are substantially rewritten (only trivial lines like braces and imports are shared), so they were left alone.
- No `Vendor/` file was touched.

## 2. Was `OpenVision/` derived from an outside project? (part d)

**Yes.** The app started from **OpenVision**, https://github.com/rayl15/OpenVision, created 9 Feb 2026, **MIT License, "Copyright (c) 2026 OpenVision Contributors"**. 98 files in this repo still exist under the same path upstream (and carry the `// OpenVision - <file>` header). Upstream also vendored kokoro-ios, MisakiSwift, and MLXUtilsLibrary.

**MIT requirements:** keep the copyright notice and permission notice in all copies or substantial portions. Status:

- Source: the full MIT text is in the root `THIRD_PARTY_NOTICES.md`, and per-file headers now point to it. **Done.**
- App binary: the notice must also ship **in the app**. **Needs a code change** (an in-app Licenses screen, checklist item L1).
- MIT permits sublicensing, so distributing the combined work under Apache-2.0 is allowed as long as the MIT notice is kept.
- The `-FIRDebugEnabled` launch argument in `project.yml` is a Firebase leftover from upstream. No Firebase SDK is linked. Harmless.

## 3. Vendored packages (part c), not relicensed

| Package | Path | License | Copyright | Apache-2.0 compatible? | App Store OK? | In NOTICE / notices? |
|---|---|---|---|---|---|---|
| kokoro-ios (KokoroSwift) | `Vendor/kokoro-ios` | MIT | © 2025 Lassi Maksimainen | Yes | Yes | Yes (full MIT text). It contains `eSpeakNGG2PProcessor.swift`, compiled only `#if canImport(eSpeakNGLib)`. **eSpeakNGLib isn't a dependency, so no GPL code is linked.** Keep it that way |
| MisakiSwift | `Vendor/MisakiSwift` | Apache-2.0 | mlalma, a port of hexgrad/misaki (Apache-2.0) | Yes | Yes | Yes. **This PR adds an explicit line to NOTICE** and credits hexgrad/misaki. Bundled resources (`us_/gb_gold.json`, `silver.json`, `bart.safetensors`) come from Misaki, Apache-2.0 |
| MLXUtilsLibrary | `Vendor/MLXUtilsLibrary` | Apache-2.0 | mlalma | Yes | Yes | Yes, with an explicit NOTICE line added. Pulls in ZIPFoundation (MIT) |

None of the three ships a NOTICE file, so Apache-2.0 §4(d) adds nothing beyond keeping their LICENSE files, which are kept.

## 4. Swift packages (part e)

From `project.yml` on `main`. Resolved versions come from the `Package.resolved` on branch `cursor/engineering-standard-conformance-df33`. **`main` has no committed `Package.resolved` yet**, so it should be committed.

| Package | Pin in project.yml | Resolved | License | Linked into app? | Flags |
|---|---|---|---|---|---|
| **meta-wearables-dat-ios** (Meta Wearables DAT) | exact 1.0.1 | 1.0.1 | **Proprietary. Meta Wearables Developer Terms + Acceptable Use Policy** (its LICENSE file only points to them) | Yes (binary xcframeworks) | Not open source, so it can't be relicensed. Meta's terms require Integration Review before a general release. **App Store distribution is still blocked by Meta's MFi position** (see `docs/APP_STORE_PLAN.md`). Ships **no privacy manifest**. Telemetry is on unless opted out |
| mlx-swift (PrismML-Eng fork) | branch `v0.31.6_prism` | 9c3a80a4ce | MIT, © 2023 ml-explore | Yes | **A branch pin isn't reproducible.** Pin a revision. The fork keeps the MIT license. Bundles MLX C++ (MIT) and Apple's metal-cpp (Apache-2.0) |
| mlx-swift-lm | revision 14414441 | same | MIT, © 2024 ml-explore | Yes | — |
| FluidAudio | **from 0.15.5** | **0.18.3** | Apache-2.0, plus: fastcluster **BSD-2-Clause** (© 2011 Daniel Müllner, © Google), vbx Apache-2.0, NemoTextProcessing (Apache-2.0, with MIT/Apache Rust crates), **LuxTTS G2P data derived from eSpeak NG (GPL-3.0-or-later) and FrequencyWords (CC-BY-SA-4.0)** | Yes | **FLAG.** In 0.18.x the default `TTS` trait links `LuxTtsG2pResources` into the app bundle. GPL-3.0-derived data in an App Store app is a known conflict (App Store usage rules vs. GPL's no-further-restrictions clause), and CC-BY-SA needs attribution and share-alike. **Fix:** `exactVersion: "0.15.5"` (no LuxTTS data, verified in its Package.swift), or keep 0.18.x with traits off. **Also add the fastcluster BSD notice** if 0.18.x stays |
| swift-huggingface | exact 1.0.0 | 1.0.0 | Apache-2.0 | Yes | Brings in EventSource (MIT, © 2025 Mattt) and swift-crypto |
| swift-transformers | exact 1.4.0 | 1.4.0 | Apache-2.0 | Yes | Brings in swift-jinja (Apache-2.0), swift-collections (Apache-2.0), swift-crypto, yyjson (MIT, © 2020 YaoYuan) |
| swift-crypto (transitive) | — | 4.5.2 | Apache-2.0, **with a NOTICE file** | Yes | §4(d): its NOTICE text must appear where notices are shown. **Added to root NOTICE.** On Apple platforms it uses CryptoKit, not BoringSSL |
| swift-asn1 (transitive) | — | 1.7.4 | Apache-2.0 | Yes | — |
| swift-numerics (transitive) | — | 1.1.1 | Apache-2.0 | Yes | — |
| swift-argument-parser (transitive) | — | 1.8.2 | Apache-2.0 | Probably not (CLI targets) | — |
| swift-syntax (transitive, build-time macros) | — | 603.0.2 | Apache-2.0 | No (compiler plugin) | — |
| WhisperKit | exact 1.1.1 | 1.1.1 | MIT, © 2024 argmax, inc. | Yes | Its server dependencies (Vapor, OpenAPI) aren't in the resolved graph |
| ZIPFoundation (transitive) | — | 0.9.20 | MIT, © 2017-2026 Thomas Zoechling | Yes | — |
| KokoroSwift | local path | — | MIT | Yes | See section 3 |

**GPL/AGPL linked into the app:** none in code. **GPL-derived data:** yes, through FluidAudio 0.18.x (fix above). **Non-commercial code:** none.

## 5. Model weights (downloaded at runtime, not bundled)

| Model | Source repo | License | Commercial use | Flags |
|---|---|---|---|---|
| Kokoro-82M (voice) | `prince-canuma/Kokoro-82M` (MLX conversion of `hexgrad/Kokoro-82M`) | Apache-2.0 | Yes | — |
| Whisper (CoreML) | `argmaxinc/whisperkit-coreml` | MIT (the original OpenAI Whisper weights are MIT) | Yes | — |
| Silero VAD (CoreML) | `FluidInference/silero-vad-coreml` | MIT | Yes | — |
| Gemma 4 E2B-it 4-bit (default local model) | `mlx-community/gemma-4-E2B-it-4bit` (base `google/gemma-4-E2B-it`) | Apache-2.0 (base model) | Yes | Confirm the mlx-community card. Its API didn't respond during this audit |
| Gemma 2 2B-it 4-bit | `mlx-community/gemma-2-2b-it-4bit` | **Gemma Terms of Use** + Gemma Prohibited Use Policy | Yes, with conditions | Must pass the use restrictions on to end users, and give a copy of the terms. Add to the Licenses screen and Terms of Use, or drop the model |
| Qwen2.5-0.5B-Instruct 4-bit | `mlx-community/Qwen2.5-0.5B-Instruct-4bit` | Apache-2.0 | Yes | — |
| **Qwen2.5-3B-Instruct 4-bit** | `mlx-community/Qwen2.5-3B-Instruct-4bit` | **Qwen Research License** | **No (non-commercial)** | **FLAG. Remove from any paid or store build** (`Services/GemmaLocal/GemmaLocalService.swift` line ~59) |
| SmolVLM2-2.2B-Instruct | `mlx-community/SmolVLM2-2.2B-Instruct-mlx` | Apache-2.0 | Yes | — |
| Bonsai-8B 1-bit | `prism-ml/Bonsai-8B-mlx-1bit` (base Qwen3-8B, Apache-2.0) | Apache-2.0 | Yes | — |
| Misaki G2P data | bundled in `Vendor/MisakiSwift/Resources` | Apache-2.0 | Yes | — |

Downloading ML weights at runtime is allowed under App Store guideline 2.5.2, because they're data, not executable code.

## 6. Relay and dev tooling (not shipped in the app)

- `relay/` has no runtime dependencies. The deployed Worker bundle is only our TypeScript.
- Dev dependencies (wrangler, vitest, typescript, @cloudflare/workers-types) are MIT or Apache-2.0. Inside wrangler's dev tooling, `sharp` pulls in **libvips binaries under LGPL-3.0-or-later**. They're used only on the developer machine and in CI, and never deployed or distributed. No action needed.

## 7. What has to happen

| # | Action | Who | Status |
|---|---|---|---|
| L1 | Add an in-app **Settings > About > Licenses / Acknowledgements** screen that shows the root `NOTICE` and `THIRD_PARTY_NOTICES.md` (bundle both as resources, or generate a plist) | Code | Needs code change |
| L2 | Pin FluidAudio to `exactVersion: "0.15.5"`, or turn off its `TTS` trait. Then confirm `LuxTtsG2pResources` isn't in the `.app` bundle | Code | Needs code change |
| L3 | Remove Qwen2.5-3B-Instruct from store builds | Code | Needs code change |
| L4 | Gemma 2 terms: show them in Licenses and pass on the prohibited-use restrictions (Terms of Use section 6 covers misuse generally), or drop the model | Code / Nicholas | Needs decision |
| L5 | Commit `Package.resolved` and pin mlx-swift to a revision | Code | Done on the conformance branch, not yet on main |
| L6 | Accept the Meta Wearables Developer Terms under the right legal entity (individual vs. LLC), and plan Integration Review | Nicholas | Needs Nicholas |
| L7 | `relay/package.json` license field and SPDX headers | This PR | **Done** |
| L8 | NOTICE lists vendored packages and the swift-crypto notice | This PR | **Done** |
