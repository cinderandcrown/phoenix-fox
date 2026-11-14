# Third-party notices

Phoenix Fox is licensed under the Apache License 2.0 by Cinder and Crown LLC (see LICENSE and NOTICE). The pieces below keep their own licenses. MIT, BSD, and Apache-2.0 code may sit inside an Apache-2.0 project. The copyright and permission text for each of those pieces is preserved here. GPL and AGPL code is not part of the app. The Meta Wearables DAT SDK is not under this project's license.

## OpenVision

The iOS app in `OpenVision/` started from OpenVision.

https://github.com/rayl15/OpenVision

MIT License

Copyright (c) 2026 OpenVision Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## WhisperKit

On-device speech to text. https://github.com/argmaxinc/WhisperKit

MIT License

Copyright (c) 2024 argmax, inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Kokoro Swift

Vendored at `Vendor/kokoro-ios`. The copy in this repo includes its own LICENSE.

MIT License

Copyright (c) 2025 Lassi Maksimainen

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## FluidAudio

Voice activity detection, already used by the wake-word path. Apache License 2.0.

https://github.com/FluidInference/FluidAudio

Copyright FluidInference and contributors. The Apache-2.0 text is the project's LICENSE.

## MisakiSwift

Vendored at `Vendor/MisakiSwift` for Kokoro's grapheme-to-phoneme step. Apache License 2.0. The vendored LICENSE file is the binding text. MisakiSwift is a Swift port of Misaki by hexgrad (https://github.com/hexgrad/misaki, Apache License 2.0), and its bundled dictionaries and G2P model come from Misaki.

## MLXUtilsLibrary

Vendored at `Vendor/MLXUtilsLibrary`. Apache License 2.0. The vendored LICENSE file is the binding text.

## mlx-swift and mlx-swift-lm

Linked as Swift packages for the optional on-device model. mlx-swift (pinned to the PrismML-Eng fork) and mlx-swift-lm are MIT License, Copyright (c) 2023 and 2024 ml-explore. The MIT text above applies with those copyright lines. They are not relicensed by Cinder and Crown LLC. The app does not link the MLXHuggingFace macro product. `LocalModelHub.swift` calls the public Hugging Face and Tokenizers APIs instead, so the build does not compile that SwiftSyntax plugin.

## swift-huggingface and swift-transformers

Pinned in `project.yml` (`swift-huggingface` 1.0.0, `swift-transformers` 1.4.0). Used to download on-device model snapshots and load their tokenizers. Upstream Apache-2.0. They are not relicensed by Cinder and Crown LLC.

## Other Swift packages linked into the app

Resolved through `project.yml`. Each is used under its own license and isn't relicensed.

MIT License (the MIT text in the OpenVision section above applies, with these copyright lines):

- ZIPFoundation: Copyright (c) 2017-2026 Thomas Zoechling. https://github.com/weichsel/ZIPFoundation
- yyjson: Copyright (c) 2020 YaoYuan. https://github.com/ibireme/yyjson
- EventSource: Copyright 2025 Mattt. https://github.com/mattt/EventSource

Apache License 2.0 (the same text as this repository's LICENSE):

- swift-crypto (SwiftCrypto). Its NOTICE is reproduced in this repository's NOTICE. https://github.com/apple/swift-crypto
- swift-asn1, swift-collections, swift-numerics, swift-argument-parser, swift-syntax (build-time only). https://github.com/apple and https://github.com/swiftlang
- swift-jinja. https://github.com/huggingface/swift-jinja

## FluidAudio bundled components

FluidAudio (Apache License 2.0) includes the following:

- fastcluster: BSD 2-Clause License. Copyright 2011 Daniel Müllner; changes from version 1.1.24 on, Copyright Google Inc. All rights reserved.

  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met: (1) Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer. (2) Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

- vbx and NemoTextProcessing: Apache License 2.0.
- **Warning:** FluidAudio 0.15.8 and later also bundle LuxTTS pronunciation data derived from eSpeak NG (GPL-3.0-or-later) and FrequencyWords (CC-BY-SA-4.0). Phoenix Fox must not ship those files. Pin FluidAudio 0.15.5 or switch off its `TTS` trait. See docs/legal/THIRD_PARTY_NOTICES.md.

## On-device model weights (downloaded at runtime, not in this repository)

- Kokoro-82M: Apache License 2.0 (hexgrad; MLX conversion by prince-canuma)
- Whisper CoreML models: MIT (argmax, inc.; original weights by OpenAI, MIT)
- Silero VAD CoreML: MIT
- Gemma 4 E2B: Apache License 2.0 (Google)
- Gemma 2 2B: Gemma Terms of Use (https://ai.google.dev/gemma/terms) and the Gemma Prohibited Use Policy (https://ai.google.dev/gemma/prohibited_use_policy). Use is subject to those restrictions.
- Qwen2.5-0.5B-Instruct: Apache License 2.0
- Qwen2.5-3B-Instruct: Qwen Research License (non-commercial). Not for commercial builds.
- SmolVLM2-2.2B-Instruct: Apache License 2.0
- Bonsai-8B (prism-ml): Apache License 2.0

## Not included

- Meta Wearables Device Access Toolkit (`meta-wearables-dat-ios`). Binary dependency only. Meta Wearables Developer Terms. No SDK source is copied into this license.
- openWakeWord pretrained models. The code is Apache-2.0, but the shipped models are Creative Commons BY-NC-SA 4.0, which is not acceptable for this commercial app. They are not in the binary.
- Picovoice Porcupine. Proprietary.
- LibreTranslate and other AGPL translation servers. Not linked.
- GPL and AGPL projects generally. Not linked.
