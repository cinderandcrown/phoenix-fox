# Phoenix Fox Disclaimers

> **Draft prepared for review; have a licensed attorney review before publishing.**

## Summary

- Phoenix Fox is an **independent app**. It isn't made, endorsed, or sponsored by Meta, Ray-Ban, Oakley, EssilorLuxottica, Apple, Google, xAI, OpenAI, or Anthropic.
- **Don't use it while driving.** It's **not a medical device**, **not an emergency service**, and **not a replacement for a cane, guide dog, or other mobility aid**.
- **AI makes mistakes.** Double-check anything that matters.

These disclaimers are part of the [Terms of Use](TERMS_OF_USE.md). Show the short versions marked **in-app copy** at the places listed in [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md).

---

## 1. No affiliation or endorsement

Phoenix Fox is developed by Cinder and Crown LLC, an independent Texas company. It **isn't affiliated with, endorsed by, sponsored by, or approved by** Meta Platforms, Inc., Ray-Ban, Oakley, EssilorLuxottica, Apple Inc., Google LLC, X.AI Corp. (xAI), OpenAI, Anthropic PBC, Cloudflare, Inc., or Marvel / The Walt Disney Company.

Phoenix Fox **works with** compatible AI glasses through Meta's Wearables Device Access Toolkit. Mentions of those products are **only to describe compatibility**. Phoenix Fox isn't "the official" app for any glasses.

> **In-app copy (About screen and App Store description):** "Phoenix Fox is an independent app that works with compatible AI glasses. It is not made by or affiliated with Meta, Ray-Ban, Oakley, Apple, xAI, OpenAI, Anthropic, or Google."

## 2. Trademarks

Meta and Meta AI are trademarks of Meta Platforms, Inc. Ray-Ban and Oakley are trademarks of their respective owners in the EssilorLuxottica group. Apple, iPhone, Siri, App Store, Apple Music, TestFlight, and Apple Intelligence are trademarks of Apple Inc., registered in the U.S. and other countries. Google, Android, Google Play, and Gemini are trademarks of Google LLC. Grok and xAI are trademarks of X.AI Corp. or its affiliates. OpenAI, ChatGPT, and GPT are trademarks of OpenAI. Claude and Anthropic are trademarks of Anthropic PBC. Cloudflare is a trademark of Cloudflare, Inc. DuckDuckGo, Tavily, and Hugging Face are trademarks of their respective owners. Other names belong to their owners. They're used only to identify compatible products and services, and their use doesn't imply endorsement.

"Phoenix Fox" and the Phoenix Fox logo are trademarks of Cinder and Crown LLC. They aren't licensed under the Apache License 2.0 or any other open-source license.

**About "Jarvis".** "Jarvis" is only the spoken wake word and the assistant's nickname inside the app. It isn't the product name. J.A.R.V.I.S. is a fictional character owned by Marvel. Phoenix Fox isn't associated with Marvel or Disney. **Store listings, screenshots, ads, and marketing must not use "Jarvis", "Iron Man", "Stark", or Marvel imagery** as a product claim.

**Store naming rule:** don't put "Meta", "Ray-Ban", or "Oakley" in the app name, subtitle, icon, or keywords. Describe compatibility factually instead ("works with compatible AI glasses"), as Meta's developer terms require (https://wearables.developer.meta.com/terms).

## 3. Safety

### 3.1 Not for use while driving

> **In-app copy (first launch, and when motion suggests driving, if implemented):** "Don't use Phoenix Fox while driving. Keep your attention on the road."

Don't use Phoenix Fox, including voice features, camera features, captions, or directions, while driving a vehicle, riding a bike or scooter in traffic, or operating machinery. Obey all traffic laws, including laws that restrict wearable devices or screens.

### 3.2 Not a medical device

Phoenix Fox isn't a medical device. It isn't intended to diagnose, treat, cure, mitigate, or prevent any disease or condition, and it hasn't been cleared or approved by the U.S. Food and Drug Administration or any other regulator. The **medication log** only records what you told it and repeats the dosing interval you logged. It doesn't give medical advice and can't tell you whether a dose is safe. The **allergen check** only matches words that on-device text recognition read. It can miss small print and never says a product is safe. Always read labels yourself and follow your doctor or pharmacist.

> **In-app copy (Workshop medication and allergen screens):** "This is a memory aid, not medical advice. Always check the label and ask your doctor or pharmacist."

### 3.3 Accessibility aids are assistive only

Reading, scene descriptions, Guide mode, walking directions, color and money identification, sound alerts, live captions, and face recognition are **assistive aids**. They can be wrong, late, or miss things entirely, for example a step, a curb, traffic, an obstacle, a siren, or a word. They **don't replace a white cane, guide dog, orientation and mobility training, a human guide, hearing aids, smoke or carbon monoxide alarms, or your own judgment.** Keep using your primary mobility aid and safety devices.

> **In-app copy (Guide mode safety notice): already done.** `GuideMode.safetyNotice` in `OpenVision/Services/Accessibility/GuideMode.swift` (line 25) already says Guide mode "will miss things, especially curbs, drop-offs, glass, and fast traffic, and it does not replace a cane, a guide dog, or your own judgment". It needs a spoken yes before the first walk (`AccessibilityCoordinator.swift`, line ~164). Keep it.

### 3.4 Not for emergencies

Phoenix Fox isn't an emergency service and can't be relied on to contact emergency services. Features such as "call my emergency contact" depend on your phone, your connection, permissions, and the glasses, and they may fail. **In an emergency, call 911** (or your local emergency number) directly from your phone.

> **In-app copy (emergency contact setting):** "This is a shortcut, not an emergency service. In an emergency, call 911 directly."

### 3.5 AI can be wrong

Phoenix Fox uses artificial intelligence, both on your phone and from providers you choose. AI output can be **inaccurate, incomplete, out of date, biased, or offensive**, and can sound confident when it's wrong. It can misread text, prices, medicine labels, signs, and faces, and it can make up facts. Verify anything important. Don't use AI output as the only basis for decisions about health, safety, money, law, or other people. When you're talking to Phoenix Fox, you're talking to an AI, not a person.

> **In-app copy (first-run and Settings > About):** "Jarvis is an AI. It can make mistakes, so check anything important."

### 3.6 Face recognition

Face recognition matches only people you saved, each of whom gave their own spoken consent, and it deletes them automatically after 30 days without a match. It can still be wrong. Never use it to make decisions about someone (for example, letting someone in or confronting someone). Never use it on people who haven't agreed. See the Privacy Policy, section 5.

### 3.7 Your surroundings and other people

Stay aware of your surroundings. Audio in your ear can mask traffic and warnings, so keep the volume at a level where you can hear what's around you. Respect other people's privacy and follow recording laws (Privacy Policy, section 8).

### 3.8 Glasses and third-party hardware

Your glasses are made and supported by their manufacturer. Follow the manufacturer's safety instructions, including for batteries, charging, heat, and eye or skin irritation. Phoenix Fox doesn't change how the glasses' hardware works and can't turn off the capture light.

## 4. Third-party services

Phoenix Fox depends on services we don't control, including Meta's toolkit and the Meta AI app, Apple's iOS services, AI providers, relays, and search engines. They can change, fail, or stop without notice. We aren't responsible for their content, availability, accuracy, or privacy practices.

## 5. No warranty

Phoenix Fox is provided "as is". See the [Terms of Use](TERMS_OF_USE.md), sections 9 and 10.
