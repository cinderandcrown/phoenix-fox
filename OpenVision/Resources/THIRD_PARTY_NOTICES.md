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

Vendored at `Vendor/MisakiSwift` for Kokoro's grapheme-to-phoneme step. Apache License 2.0. The vendored LICENSE file is the binding text.

## MLXUtilsLibrary

Vendored at `Vendor/MLXUtilsLibrary`. Apache License 2.0. The vendored LICENSE file is the binding text.

## mlx-swift and mlx-swift-lm

Linked as Swift packages for the optional on-device model. Their upstream licenses apply (mlx-swift is commonly MIT; confirm the tag pinned in the Xcode project before a store submission). They are not relicensed by Cinder and Crown LLC. The app does not link the MLXHuggingFace macro product. `LocalModelHub.swift` calls the public Hugging Face and Tokenizers APIs instead, so the build does not compile that SwiftSyntax plugin.

## swift-huggingface and swift-transformers

Pinned in `project.yml` (`swift-huggingface` 1.0.0, `swift-transformers` 1.4.0). Used to download on-device model snapshots and load their tokenizers. Upstream Apache-2.0. They are not relicensed by Cinder and Crown LLC.

## Not included

- Meta Wearables Device Access Toolkit (`meta-wearables-dat-ios`). Binary dependency only. Meta Wearables Developer Terms. No SDK source is copied into this license.
- openWakeWord pretrained models. The code is Apache-2.0, but the shipped models are Creative Commons BY-NC-SA 4.0, which is not acceptable for this commercial app. They are not in the binary.
- Picovoice Porcupine. Proprietary.
- LibreTranslate and other AGPL translation servers. Not linked.
- GPL and AGPL projects generally. Not linked.
