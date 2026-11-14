// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import Foundation

/// In-app privacy policy text (Guideline 5.1.1). Keep aligned with docs/PRIVACY_POLICY.md.
enum PrivacyPolicyDocument {
    static let title = "Privacy Policy"
    static let effective = "Effective 14 November 2026"

    static let body = """
    Publisher: Cinder & Crown LLC
    App: Phoenix Fox (com.cinderandcrown.phoenixfox)

    Summary
    Cinder & Crown does not run a Phoenix Fox cloud account and does not collect analytics, advertising IDs, or crash data from the app by default. What you say, type, or capture is processed on your iPhone or sent to services you choose (your AI provider keys, your own relay, optional self-hosted telemetry). Meta’s apps and glasses software handle pairing under Meta’s terms when you connect compatible AI glasses.

    Data on your iPhone
    Phoenix Fox stores settings, API keys and tokens (Keychain), optional notes and memories, accessibility data you enable, and caches for on-device models. Erase local app data from Settings → Privacy & Data.

    Cloud AI providers (optional)
    If you paste an API key or sign in to a provider (xAI Grok, OpenAI / ChatGPT, Anthropic Claude, Google Gemini) or connect your own assistant relay, your voice transcripts, typed prompts, and any photos you attach are sent to that provider so it can answer. Those providers process data under their privacy policies. You must accept Cloud AI data sharing consent before the first cloud send. Withdraw anytime in Privacy & Data; on-device answers keep working.

    Glasses and Meta
    Connecting glasses uses Meta’s Wearables Device Access Toolkit and the Meta AI app. Camera frames are requested only when you ask Jarvis to look (or use a feature that needs a look). The capture light stays on while the camera is in use; Phoenix Fox cannot turn that light off.

    Permissions
    System permissions are requested only for features you use. Deny a permission and that feature will not work.

    Purchases
    If subscriptions are offered through the App Store, Apple processes payment. Cinder & Crown receives entitlement status from StoreKit, not your full payment card details.

    Children
    Phoenix Fox is not directed at children under 13 and is not Made for Kids.

    Contact
    Use Settings → Privacy & Data → Report a concern, or the publisher email on the App Store product page.

    Changes
    The effective date above changes when this policy updates. The full markdown source lives in the project as docs/PRIVACY_POLICY.md for hosting at a public HTTPS URL before sale.
    """
}
