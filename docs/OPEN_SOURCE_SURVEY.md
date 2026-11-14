# Open source survey

What Phoenix Fox looked at for a daily-use glasses companion, what is worth taking, and what was left out. Only MIT, Apache-2.0, and BSD code is eligible for the app binary. GPL and AGPL are not. The Meta DAT SDK is used as Meta ships it and is not relicensed. Attributions are in THIRD_PARTY_NOTICES.md.

| Project | License | Maturity | Worth adopting? | Decision |
| --- | --- | --- | --- | --- |
| [OpenVision](https://github.com/rayl15/OpenVision) | MIT | A working iOS app on DAT: pairing, camera, wake word, VAD, TTS, several model backends. | Yes. It is the base. | Adopted. MIT notice kept in full. |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | MIT | Current Swift package, Core ML Whisper, used in production apps. | Yes, for on-device speech after the wake word. | Adopted. Base model, Apple speech if the model is not ready. |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache-2.0 | Active Swift SDK. Silero-style VAD on the Neural Engine, which is the low-power gate before Whisper. | Yes. Already in OpenVision. | Kept. Whisper does not run on silence. |
| Kokoro Swift (`Vendor/kokoro-ios`) | MIT | Usable on-device neural voice. Heavy. | Optional voice, not the default. | Kept in the tree. Apple's system voice is the default so a normal turn costs nothing. |
| MisakiSwift and MLXUtilsLibrary | Apache-2.0 | Vendored with Kokoro. | Only as Kokoro's dependencies. | Kept. Notices point at the vendored LICENSE files. |
| [OpenJarvis](https://github.com/open-jarvis/openjarvis) | Apache-2.0 | Python, local-first assistant: morning digest, monitor agents, skills. Not an iOS glasses app. | The patterns, not the code. Porting the Python stack into the phone would not make pairing or battery better. | Not compiled in. The relay, morning brief, and "take over" dispatch follow the same idea: the phone is the ears, the assistants do the work. |
| [openWakeWord](https://github.com/dscripka/openWakeWord) | Code Apache-2.0. Pretrained models CC BY-NC-SA 4.0. | Mature Python/ONNX wake word. The models are non-commercial and share-alike. | The idea of a small spotter before the big model. Not the weights. | Not adopted. A commercial app cannot ship those models. Wake word stays Apple's recognizer biased toward "Jarvis", gated by the FluidAudio VAD. |
| Picovoice Porcupine | Proprietary | Polished wake word. | No. | Not used. |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | MIT | Very mature C++ Whisper. | Overlaps WhisperKit, which is the Swift path and already linked. A second runtime would cost battery and build time. | Not added. |
| Piper, sherpa-onnx | MIT / Apache-2.0 | Good offline TTS and speech stacks, mostly C++. | Possible later. Kokoro plus Apple speech already cover the ear. | Not added in this build. |
| Meta DAT samples and `meta-wearables-dat-ios` | Meta Wearables Developer Terms, not MIT/Apache | The official SDK. 1.0.1 is the pinned release. | Required for the camera, registration, and device state. | Linked. Source is not copied and is not under the Apache-2.0 LICENSE. |
| MentraOS and other smart-glasses assistants | Often Apache-2.0, different hardware and protocol | Active, not a DAT iOS client. | UX only: one obvious connection state, reconnect without a lecture, listening that does not burn the camera. | Patterns used in GlassesLink and the status line. No Mentra code. |
| LangChain and typical RAG servers | MIT, but a server stack | Wrong place for a glasses turn. | On-device search is enough for "where did I park". | Not added. Memory is CryptoKit plus Apple's `NLEmbedding`, written here. |
| LibreTranslate and Argos as a service | AGPL for the server many people run | Fine as someone else's server. | Must not be linked or vendored. | Not used. Spoken translation is one short Grok call, or it refuses. |

## What that means for daily use

Pairing and reconnect stay on the official DAT session. The status line says whether the mic is listening and whether the camera light is on. Listening uses the VAD that was already in OpenVision, then Whisper only after speech. The camera starts for a look, a watch, or a recording, and the hardware LED stays in Meta's control. Simple answers stay on the phone or on one cheap model. Fire Fox, Indy, Driver, and Rally get the work that is actually a task.

## Not adopted, on purpose

GPL and AGPL code. openWakeWord's non-commercial models. Any sample that would hide the capture LED or record without a spoken request. Meta's SDK source, which we do not have the right to relicense.
