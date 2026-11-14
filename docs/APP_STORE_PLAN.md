# App Store plan

Publisher: **Cinder & Crown LLC** (Texas).  
Public name: **Phoenix Fox**. Bundle ID: `com.cinderandcrown.phoenixfox`. Meta App ID: `1651172483404286` (Wearables project Phoenix Fox, organization Cinder and Crown LLC).  
Spoken wake word and voice nickname: **Jarvis**. That name is not the App Store name, the home-screen name, the bundle id, or the publisher.  
Position: any AI, your glasses. Not a Meta AI client and not tied to one model vendor.

This is a plan, not a filing. Nothing here has been submitted to Apple or Meta.

## The glasses he will test first

**"Adventurer" is Meta Glasses Adventurer.**

It is Meta's own-brand displayless frame (rectangular sunglasses, sold on meta.com as Meta Glasses Adventurer). It is not a Ray-Ban style, not an Oakley style, and not Meta Ray-Ban Display. The camera, microphones, and open-ear speakers match the Ray-Ban Meta (Gen 2) class. There is no in-lens display and no Neural Band in the box.

The Wearables Device Access Toolkit supports it.

- SDK enum: `DeviceType.metaGlasses` ("a Meta-branded smart glasses device without an integrated display").
- Meta's toolkit hardware list names "Meta glasses" alongside Ray-Ban Meta, Ray-Ban Meta Optics, Oakley Meta HSTN, Oakley Meta Vanguard, and Meta Ray-Ban Display.
- Toolkit **1.0.1** (the version this repo pins) lists Meta glasses firmware **V128** and Meta AI app **V292** as the supported pair. See [version dependencies](https://wearables.developer.meta.com/docs/develop/dat/version-dependencies/).

**v1 test:** audio plus camera on Adventurer. Pair in the Meta AI app, speak, hear the reply, ask for one photo. Display and Neural Band code stays behind `supportsDisplay` and input-source checks. A missing display is the normal Adventurer result, not a failure. Detail is in [GLASSES_SDK.md](GLASSES_SDK.md).

**v2 roadmap, not a v1 blocker:** Meta Ray-Ban Display HUD cards, and Neural Band gestures mapped from semantic events (`select`, `nav`, `drag`). The SDK does not expose raw EMG. Those paths must no-op on Adventurer.

## Go / no-go for public sale

**No-go for a public App Store sale today** (14 November 2026).

Full ranked checklist: [APP_STORE_REVIEW_AUDIT.md](APP_STORE_REVIEW_AUDIT.md). Pasteable review notes: [APP_STORE_REVIEW_NOTES.md](APP_STORE_REVIEW_NOTES.md).

Two independent blockers:

1. **Meta will not let this binary into the public App Store yet.** The iOS integration guide still says publishing to the App Store is not supported, because the SDK uses `ExternalAccessory` / `com.meta.ar.wearable` and Apple then requires MFi authorization that only Meta can grant. Meta staff confirmed again in [Discussion #313](https://github.com/meta/meta-wearables-dat-ios/discussions/313) (September 2026) that DAT 1.0 does not change this, and in [Issue #266](https://github.com/meta/meta-wearables-dat-ios/issues/266) (10 August 2026) that there is no waitlist. Meta’s FAQ (checked 14 November 2026) says discovery/submission are “soon” but does not open App Store + PPID. The allowed path today is a Wearables Developer Center release channel plus TestFlight for invited testers.
2. **Store listing name.** The public product is Phoenix Fox, from Cinder & Crown LLC. Do not put **Meta** or **Ray-Ban** in the app name, icon, or subtitle. Meta's developer terms do not grant use of their brand features beyond a factual description of compatibility. Say "works with compatible AI glasses", not "the official Meta Ray-Ban app". Jarvis is only the word he says and the voice that answers. It is not on the App Store page.

OpenVision's MIT license allows a commercial derivative if the copyright and license notice stay in the app and repo. Vendored Kokoro is MIT. Misaki is Apache-2.0. WhisperKit is MIT. The Meta SDK is not open source. Using it means accepting the [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms) (updated 6 October 2025): a limited license to build integrations for Meta-approved glasses, Integration Review before a general release, and no implication of sponsorship. Experimental toolkit features (on-glasses speech, motion, and the newer display and input modules where Meta still labels them experimental) cannot be the thing a production build depends on.

## What he can do before public sale

Install his own build with TestFlight after the GitHub secrets exist. That is the Mac-free path in [SETUP.md](SETUP.md). His Adventurer still has to be on a Meta release channel for that app id, or the glasses will not complete registration. TestFlight does not remove that Meta step.

## Brains

One protocol (`AIBackend` plus `BrainCatalog`). Providers are peers:

- On this iPhone (Apple, and the on-device model already in OpenVision)
- xAI Grok
- Anthropic Claude
- OpenAI
- Google Gemini Live
- Your own assistant, over the relay. That is how his Grok Bots connect. The same protocol fits a future assistant platform, including anything Anthropic ships later. No vendor is hard-wired into the glasses loop.

Fast mode sends short talk and "what am I looking at" to the configured vendor's quick model. The defaults (`grok-4.20-non-reasoning`, `claude-haiku-4-5`, and `gpt-4o-mini`) are no longer the cheapest each vendor sells. [BUSINESS_MODEL.md](BUSINESS_MODEL.md) has the prices and what to change. Tasks, notes, briefings, and all-hands go to the relay. Silence stays on the phone: wake word and voice activity detection, Apple speech as the fallback, Apple voice as the default speaker.

## Money

The plan, the prices, what each feature costs to run, and the margins are in [BUSINESS_MODEL.md](BUSINESS_MODEL.md). That page replaces the earlier sketch here, which had one paid tier at $12.99 and cost figures with no sources.

In short:

- **Free:** the whole accessibility suite, the wake word, and the model on the phone. It costs nothing for each use and is never locked.
- **Own AI:** cloud models with the subscriber's own key.
- **Included AI:** a model paid for by Cinder & Crown, inside a monthly allowance. Not offered until a metered service exists.
- **Bot Team:** more than one assistant, by name, and all hands.

One thing changed from the earlier sketch: using your own key was free there and is the lowest paid plan now. That is the owner's call, and [BUSINESS_MODEL.md](BUSINESS_MODEL.md) says how to make it free again.

The subscription code is in the app and switched off. The owner's TestFlight build has everything unlocked and nothing for sale.

Do not put his relay URL, token, or bot names in the binary. He types those after install.

## Launch steps, when Meta opens the store

1. Ship the listing as Phoenix Fox. No Meta or Ray-Ban in the name. Jarvis stays the wake word inside the app.
2. Confirm the iOS guide no longer blocks App Store submission, and that Meta has either dropped the MFi protocol or authorized this bundle id.
3. Pass Meta Integration Review for this app id. Adventurer (Meta glasses, firmware on the 1.0.1 table) is the hardware named in the review notes.
4. Enroll Cinder & Crown's Apple Developer account, create the App Store Connect API key, and let GitHub Actions upload. He does not need a Mac. Steps are in SETUP.md.
5. Host the privacy policy and terms, and paste the review notes from this folder. The app will not sell anything until the privacy policy's address is in `StoreCatalog.privacyURL`.
6. Create the subscription group and products, and build with `PHOENIX_FOX_STORE=YES`. The steps are in [BUSINESS_MODEL.md](BUSINESS_MODEL.md).
7. Turn anything hosted on only after its allowance is enforced on the server. Until then, buyers bring their own key or their own assistants.
