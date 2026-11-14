# App Store plan

Publisher: **Cinder & Crown LLC** (Texas).  
Working name in the app: **Jarvis**.  
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

Two independent blockers:

1. **Meta will not let this binary into the public App Store yet.** The iOS integration guide still says publishing to the App Store is not supported, because the SDK uses `ExternalAccessory` / `com.meta.ar.wearable` and Apple then requires MFi authorization that only Meta can grant. Meta staff said in August 2026 they will not add third-party bundle ids to that plan or issue a PPID, and there is no waitlist. Toolkit 1.0 shipped as a stable SDK in September 2026, and Meta's FAQ says discovery and submission are "soon", but the iOS page and the MFi answer have not been lifted. The allowed path today is a Wearables Developer Center release channel plus TestFlight for invited testers.
2. **The name "Jarvis"** collides with Marvel's J.A.R.V.I.S. Do not ship a paid app under that name without a clearance. The product also must not put **Meta** or **Ray-Ban** in the app name, icon, or subtitle. Meta's developer terms do not grant use of their brand features beyond a factual description of compatibility. Say "works with compatible AI glasses", not "the official Meta Ray-Ban app".

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

Fast mode sends short talk and "what am I looking at" to the cheapest configured instant model (Grok fast non-reasoning, Claude Haiku, or `gpt-4o-mini`). Tasks, notes, briefings, and all-hands go to the relay. Silence stays on the phone: wake word and voice activity detection, Apple speech as the fallback, Apple voice as the default speaker.

## Money

Free: one assistant, on-device or his own API key, wake word, one-photo look.  
Pro, suggested **$12.99 a month or $99 a year**: more than one assistant, all-hands, priority alerts, and a hosted relay with a cap of about 200 cheap cloud turns a month. Past the cap, he uses his own key.

Do not put his relay URL, token, or bot names in the binary. He types those after install.

### Cost, per request (planning estimates, recheck before charging anyone)

Figures are order-of-magnitude for a cheap vision model in late 2026, not a quote. On-device work is $0. A relay task is billed by whoever runs his assistant, not by Cinder & Crown, unless he is on the hosted cap.

| What he does | Leaves the phone? | Who is paid | Rough cost |
| --- | --- | --- | --- |
| Glasses idle, wake word listening | No. Voice activity detection drops silence. | Nobody | $0 |
| Short question, no photo | A few hundred tokens | Cheap instant model | about $0.001 |
| "What am I looking at" | One compressed JPEG, camera off again | Cheap instant model | about $0.003 to $0.008 |
| "Look at this" or a task (email, order, schedule) | Text, plus a photo only if he asked | His assistant, via the relay | his bill |
| Briefing or all-hands | One request, spoken in sequence | His assistants | his bill |
| Alert while the app is open | Long-poll, not a poll every second | Cloudflare, pennies | under $0.01 |
| Snapshot mode | Off unless he turns it on | Same as a photo | do not leave it on |

**Target:** $0 cloud cost for a free user who stays on-device. **Under $3 a month** of model and relay cost for a hosted Pro user inside the 200-turn cap. Price Pro at $12.99 so the cap, not a heavy user, sets the cost. Adventurer's camera stays off except for an explicit look, which is the main battery and upload saving.

## Launch steps, when Meta opens the store

1. Rename the app if "Jarvis" is not cleared. No Meta or Ray-Ban in the name.
2. Confirm the iOS guide no longer blocks App Store submission, and that Meta has either dropped the MFi protocol or authorized this bundle id.
3. Pass Meta Integration Review for this app id. Adventurer (Meta glasses, firmware on the 1.0.1 table) is the hardware named in the review notes.
4. Enroll Cinder & Crown's Apple Developer account, create the App Store Connect API key, and let GitHub Actions upload. He does not need a Mac. Steps are in SETUP.md.
5. Host the privacy policy and terms, and paste the review notes from this folder.
6. Turn the hosted relay on only after the cost cap is enforced. Until then, buyers bring their own key or their own assistant.
