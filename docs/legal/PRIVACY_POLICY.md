# Phoenix Fox Privacy Policy

> **Draft prepared for review; have a licensed attorney review before publishing.**
>
> Items in **[brackets]** must be filled in or decided before this is published. Open questions are listed at the end.

**Effective date:** [DATE OF PUBLICATION]
**Last updated:** [DATE]

## Summary

- Phoenix Fox is a companion app for AI glasses. It has **no accounts and no ads, and we don't sell or share your data for advertising**. We don't run a server that stores your conversations.
- Most of what Phoenix Fox does happens **on your iPhone**: the wake word, speech recognition where your phone supports it, reading text, sound alerts, and the built-in voice.
- When you choose a cloud AI (for example Grok from xAI, ChatGPT from OpenAI, Claude from Anthropic, or Gemini from Google), what you say, recent conversation, and any picture you ask about are **sent to that company** under your own key or sign-in. Their privacy policy covers it from then on.
- The glasses camera works only when you ask, and the glasses' capture light is on whenever it does. Phoenix Fox can't turn that light off.
- **Optional face recognition** can remember people you name, but only after you confirm they agreed. Face data stays encrypted on your phone and is never sent to us or anyone else. It's off unless you turn it on.
- You must be **18 or older** to use Phoenix Fox.
- You can delete your data in the app or by deleting the app. Contact: **cinderandcrown@gmail.com**.

## 1. Who we are

Phoenix Fox ("the app") is published by **Nicholas Will**, an individual developer based in Dallas, Texas, USA ("we", "us", "our"). [OPEN QUESTION: if the app is moved to Cinder and Crown LLC, replace this with "Cinder and Crown LLC, a Texas limited liability company".]

Contact: **cinderandcrown@gmail.com** [OPEN QUESTION: a dedicated address such as privacy@cinderandcrown.com is recommended]
Mailing address: **[MAILING ADDRESS]**

For the EU and UK GDPR, we are the "controller" only for the limited personal data we actually receive (see section 6). For data you send directly to an AI provider or other service you choose, that provider decides how it's used.

## 2. What this policy covers

This policy covers the Phoenix Fox iPhone app, its TestFlight beta, and any future Android version with the same features. It doesn't cover Meta's glasses, the Meta AI app, Apple's services, or the AI providers and other services you connect. Each has its own privacy policy.

## 3. What stays on your phone

These are processed **only on your iPhone** and aren't sent to us:

| Data | What it's used for | How long it's kept |
|---|---|---|
| Voice audio for the wake word and commands | Hearing "Jarvis" and what you say. When your phone supports on-device recognition and that setting is on, Apple's speech recognition runs on the phone | Not saved |
| Sounds around you (sound alerts, if on) | Telling you about sirens, alarms, doorbells and similar sounds, using Apple's on-device sound classifier | Not recorded |
| Live captions, and saved transcripts (if "keep transcripts" is on) | Captions, and looking back at what was said | Until you delete them |
| Camera frames from the glasses | Reading text, money, labels, colors, and describing scenes with on-device models when available | Frames aren't saved. Photos you save go to your Photos library |
| Face prints (only if you turn on face recognition) | See section 5 | Until you delete them |
| Conversation history, memories, custom instructions, settings | Your history and personalization | Until you delete them. Conversation history and settings are included in your iCloud or computer backup if you back up your phone |
| Medication log, allergen list, notes, routines, reminders, journal, tallies | Your personal tools in the app | Until you erase them. Stored encrypted on the phone and excluded from backups |
| Location | "Where am I", walking directions, and reminders when you arrive somewhere | Not stored, except a place name on a note you save and the area of a reminder you set |
| Contacts, calendar, reminders, photos, music | Only when you ask: looking up a contact to call or text, reading or adding events, saving a photo, playing music | Phoenix Fox doesn't copy your contacts, calendar, or library |
| API keys, sign-in tokens, relay token | Connecting to the services you chose | Stored in the iOS Keychain until you remove them |
| On-device AI models | Offline answers and the built-in voice | Until you delete them |

Phoenix Fox uses iOS permissions for the microphone, speech recognition, camera (through the glasses), Bluetooth, local network (to join the Wi-Fi the glasses create for the camera), location, contacts, calendars, reminders, photos, Apple Music, and notifications. You can refuse or withdraw any of them in the iOS Settings app. Features that need a permission won't work without it, but the rest of the app will.

## 4. What leaves your phone, and who gets it

### 4.1 AI providers you choose

Phoenix Fox works with several AI providers. You choose which ones to use, and you connect them with **your own API key or your own sign-in** to that provider. The default is Grok from xAI.

| Provider | Addresses the app contacts |
|---|---|
| xAI (Grok) | api.x.ai, auth.x.ai |
| OpenAI (ChatGPT) | api.openai.com, auth.openai.com, chatgpt.com |
| Anthropic (Claude) | api.anthropic.com |
| Google (Gemini) | generativelanguage.googleapis.com |

**What can be sent to the provider you choose:** what you say (as text), recent turns of the conversation, your custom instructions, saved memories (for some providers), the results of tools the assistant used for you (for example calendar events, note text, or web search results), and **pictures from the glasses camera when you ask the assistant to look**. In live mode with OpenAI or Gemini, your **voice audio and camera video are streamed** for as long as live mode is on. If you pick a cloud voice from xAI or OpenAI, the assistant's reply text is sent to turn it into speech.

- **Before anything is sent to an AI provider, Phoenix Fox asks your permission** and names the provider. [CODE CHANGE REQUIRED: this consent screen doesn't exist yet. See REVIEW_CHECKLIST.md. Don't publish this sentence until it ships.]
- Data goes **straight from your phone to the provider**, not through us. The provider's terms and privacy policy apply. They may keep data for abuse monitoring, and depending on your account settings, they may use it to improve their models. Check their settings and policies: [xAI](https://x.ai/legal/privacy-policy), [OpenAI](https://openai.com/policies/privacy-policy), [Anthropic](https://www.anthropic.com/legal/privacy), [Google](https://policies.google.com/privacy).
- Because you use your own key or sign-in, the provider can link these requests to your account with them.
- If one provider doesn't answer, Phoenix Fox may try the next one you set up (in the order Grok, Claude, ChatGPT, then on-device). A provider is used only if you've connected it.
- **Guide mode** (for blind and low-vision users) may send scene pictures to your cloud AI when no on-device model can describe the scene. You can turn off "cloud descriptions" in Accessibility settings. [CODE CHANGE RECOMMENDED: make this off by default, or ask the first time.]
- On-device AI ("on this iPhone") sends nothing.

### 4.2 Your own assistants, relays, and gateways

You can connect Phoenix Fox to **your own** AI assistants through a relay you run (a small Cloudflare Worker), or to a self-hosted gateway (OpenClaw or Hermes). When you do, the text of your request, its transcript, recent conversation, and any pictures you include go to **the relay or gateway address you enter**, and from there to the assistants its operator has configured.

The relay in this project keeps a request for **15 minutes** and a message waiting for you for **24 hours**, then deletes it. It also keeps your phone's push notification token so it can tell you when a task is done. Cloudflare, which hosts the relay, may keep request logs (such as IP address, time, and address requested) for a limited time under its own policy. Whoever runs the relay is responsible for it. The developer's personal relay is used only for the developer's own assistants and isn't offered to other users.

### 4.3 Web search

When the assistant searches the web for you, the search words go to **DuckDuckGo**, or to **Tavily** if you added a Tavily key. Their privacy policies apply.

### 4.4 Meta (glasses)

Your glasses connect through Meta's Wearables Device Access Toolkit and the Meta AI app. You pair the glasses and grant camera and microphone access to Phoenix Fox in the Meta AI app. Meta's toolkit sends Meta **technical telemetry** such as the app's ID and version, your phone model and OS version, a glasses device identifier, firmware version, and connection, permission, and error events. Meta uses it for reliability and product improvement under [Meta's privacy policy](https://www.meta.com/legal/privacy-policy/). [CODE DECISION: we recommend switching this telemetry off with Meta's opt-out setting. If that's done, replace this paragraph with "Phoenix Fox switches off the optional telemetry in Meta's toolkit."] Your use of the glasses and the Meta AI app is governed by Meta's terms.

### 4.5 Apple

Apple processes data when Phoenix Fox uses Apple services: speech recognition on Apple's servers (only when on-device recognition is unavailable or switched off), Apple Maps and address lookup, push notifications, iCloud backups you've turned on, and App Store purchases. Apple's privacy policy applies. When you buy a subscription, Apple handles payment. We don't get your card details, and the app doesn't send us your purchase history.

### 4.6 Model downloads

On-device models are downloaded from **Hugging Face**, which sees your IP address and which model was requested.

### 4.7 Telemetry you control

Phoenix Fox can send performance numbers to **your own** InfluxDB server if you turn on telemetry and enter its address. It's off by default and never goes to us.

### 4.8 Calls, texts, and email

When you ask Phoenix Fox to call, text, or email someone, it looks up the contact on your phone and opens the Phone, Messages, Mail, or WhatsApp app with the message filled in. **Phoenix Fox asks you to confirm by voice, and you send it yourself.** Phoenix Fox doesn't send messages, place calls, buy anything, or post anything without your spoken confirmation.

## 5. Face recognition and biometric data

**What it does.** If you turn on face recognition and say "remember this person as [name]", Phoenix Fox first asks: "Has [name] agreed to let me save their face on this phone?" It saves only if you say yes. It then makes a mathematical **face print** from the picture with Apple's on-device Vision framework, and stores up to five prints per person, along with the name, the date you confirmed consent, and the last time they were recognized. Later, when you ask who's in front of you, it compares faces in view with the people you saved. If the match isn't clear, it says it isn't sure rather than guess.

**What it doesn't do.** It doesn't identify strangers, search the internet, or compare faces against any database other than the people you saved. Face prints are **never sent** to us, an AI provider, Meta, or anyone else. They're encrypted on your phone with a key that can't leave the device, and excluded from backups.

**Your responsibility.** Biometric privacy laws, including the **Illinois Biometric Information Privacy Act (740 ILCS 14)**, the **Texas Capture or Use of Biometric Identifier Act (Tex. Bus. & Com. Code § 503.001)**, **Washington's biometric identifier law (RCW 19.375)**, and the **GDPR (Article 9)**, may require **the informed, and sometimes written, consent of the person whose face is saved**. Save someone only if they've clearly agreed, and delete them if they ask. Don't use face recognition where the law doesn't allow it. [OPEN QUESTION / ATTORNEY: see REVIEW_CHECKLIST.md about whether to turn this feature off in the public release or in certain states.]

**Retention and deletion.** Say "forget [name]'s face" or "forget all faces", or use **Settings > Accessibility > Delete all saved faces**. Deleting the app deletes them too. [CODE CHANGE RECOMMENDED: automatically delete a saved person not recognized for 12 months. Texas law requires destruction within a reasonable time, and no later than one year after the purpose expires. Illinois requires a published retention schedule with destruction no later than three years after the last interaction. Until that ships, the retention schedule is: kept until you delete it or delete the app.]

Phoenix Fox doesn't use face data for advertising, profiling, or anything other than telling you who you saved.

## 6. What we (the developer) receive

We don't operate an account system, an analytics service, a crash reporter, or an advertising SDK in the app. We receive only:

- **From Apple:** sales and subscription reports without your identity, and crash reports and app usage data only if you chose to share them with app developers in iOS Settings.
- **From Meta:** the developer-console view of the toolkit telemetry described in 4.4 (if it stays on).
- **If you join the TestFlight beta:** your name and the email you used to accept the invitation, and anything you choose to send through TestFlight feedback (which can include screenshots). In beta builds that include an in-app "report a bug" feature, the report (your note, what you said when you reported it, app version, and diagnostics with personal details removed) goes to the developer's relay and is deleted after 30 days.
- **If you email us:** your email and message.

**Legal bases (EU/UK):** performing our agreement with you (Article 6(1)(b) GDPR) to provide the app and handle support; your consent (Article 6(1)(a)) for beta feedback, and for anything you send to an AI provider through the app; our legitimate interests (Article 6(1)(f)) in keeping the app working and secure. Face recognition, where the GDPR applies, relies on your explicit consent and the consent of the person saved (Article 9(2)(a)). Processing you do purely for personal or household purposes is outside the GDPR (Article 2(2)(c)).

## 7. We don't sell or share personal data

We don't **sell** personal information, and we don't **share** it for cross-context behavioral advertising, as those terms are used in the California Consumer Privacy Act (Cal. Civ. Code § 1798.100 et seq.). We don't use **targeted advertising** or **profiling** with legal or similarly significant effects, as defined in the Texas Data Privacy and Security Act (Tex. Bus. & Com. Code ch. 541) and similar state laws. Phoenix Fox doesn't track you across other companies' apps or websites.

**Sensitive data.** Some data Phoenix Fox can handle is "sensitive" under state laws: precise location, biometric data (face prints), health-related notes (the medication log), and the content of communications. Phoenix Fox processes it only on your phone, or sends it to a service only when you ask. It doesn't use it to infer characteristics about you. Where a law requires consent to process sensitive data, Phoenix Fox asks first.

## 8. Cameras, microphones, and people around you

AI glasses can capture people who didn't agree to it. Please be respectful:

- The glasses' **capture light** is on whenever the camera is in use. Don't cover it or try to defeat it.
- **Recording-consent laws.** Under federal law (18 U.S.C. § 2511(2)(d)) and in Texas (Tex. Penal Code § 16.02), one party to a conversation may generally record it. Several states require **everyone's consent** to record a private conversation, including California (Cal. Penal Code § 632), Florida (Fla. Stat. § 934.03), Illinois (720 ILCS 5/14-2), Maryland (Md. Code, Cts. & Jud. Proc. § 10-402), Massachusetts (Mass. Gen. Laws ch. 272, § 99), Montana (Mont. Code Ann. § 45-8-213), New Hampshire (N.H. Rev. Stat. § 570-A:2), Pennsylvania (18 Pa. C.S. § 5703), and Washington (RCW 9.73.030). Other states and countries have their own rules. This list isn't complete and isn't legal advice. **You're responsible for following the law where you are.**
- Live captions, saved transcripts, session recordings, live mode, and pictures sent to an AI can capture other people's words and faces. Tell people when you're using them, and stop if anyone objects.
- Don't use Phoenix Fox in places where recording is prohibited or expected to be private, such as restrooms, locker rooms, medical settings, or places that post a no-recording notice.

## 9. Children

Phoenix Fox isn't directed to children, and **you must be at least 18 to use it**. We don't knowingly collect personal information from children under 13, as defined by the Children's Online Privacy Protection Act (15 U.S.C. §§ 6501-6506; 16 C.F.R. Part 312), or from anyone under 18. If you believe a child has given us personal information, email us and we'll delete it.

## 10. How long data is kept

| Where | How long |
|---|---|
| On your phone | Until you delete it in the app or delete the app. Face prints: see section 5 |
| A relay | Requests 15 minutes. Messages waiting for you 24 hours. Push token until Apple reports it invalid or it's one of more than 8 devices. Beta bug reports 30 days |
| AI providers, Meta, Apple, Cloudflare, search services, Hugging Face | Under their own policies |
| Email to us | As long as needed to answer you, and then up to [24 months] unless the law requires longer |
| TestFlight tester details | While the beta runs, and deleted within [90 days] after it ends |

## 11. Deleting your data

- **In the app:** delete conversations in History. Use **Settings > Accessibility > Delete all saved faces**, and **Settings > Workshop > Erase everything the workshop keeps**. Delete saved transcripts. Remove keys and sign-ins in each provider's settings. [CODE CHANGE REQUIRED: add a single "Delete all my data" button. See checklist.]
- **Everything:** deleting the app removes its data from your phone. Keychain items may remain until you reset the phone, but no other app can read them.
- **At a provider:** use that provider's controls to delete your history with them.
- **With us:** email cinderandcrown@gmail.com and we'll delete any email, beta report, or tester details we hold.

There's no Phoenix Fox account to delete. If accounts are added later, this policy will explain how to delete one, in the app and on the web.

## 12. Security

API keys and tokens are kept in the iOS Keychain. Face prints, transcripts, and the accessibility and workshop data are encrypted with AES-GCM using a key that never leaves the phone. Connections to AI providers and the relay use HTTPS. The relay requires a secret token for every request. No system is perfectly secure. Protect your phone with a passcode, and don't share your keys or relay token. Report security issues to cinderandcrown@gmail.com.

## 13. International transfers

We're in the United States. Providers you connect may process data in the United States or other countries. When you're in the EEA, the UK, or Switzerland and you choose to send data to a provider, that provider's transfer mechanism applies (for example the EU-U.S. Data Privacy Framework or Standard Contractual Clauses). For the little data we receive (section 6), we process it in the United States.

## 14. Your rights

Depending on where you live, you may have the right to access, correct, delete, or get a copy of your personal data, to object to or restrict processing, to withdraw consent, and to opt out of sale, sharing, targeted advertising, and profiling. This includes the GDPR and UK GDPR (Articles 15-22), the CCPA/CPRA (Cal. Civ. Code §§ 1798.100-1798.199.100), the Texas Data Privacy and Security Act (Tex. Bus. & Com. Code § 541.051), and similar laws in other U.S. states. We don't sell or share data, and we don't do targeted advertising or profiling, so there's nothing to opt out of. You can still ask.

Most of your data is only on your phone, and you control it directly (section 11). For anything we hold, email **cinderandcrown@gmail.com** with the subject "Privacy request". We'll respond within 45 days (or one month under the GDPR), and may extend that once where the law allows. We may need to verify your request. You can use an authorized agent where the law allows.

**Appeals (Texas and other U.S. states).** If we decline your request, you can appeal by replying with the subject "Privacy appeal". We'll answer within 60 days. If you're unhappy with the result, you can contact your state attorney general. In Texas, that's https://www.texasattorneygeneral.gov/consumer-protection.

**EU/UK.** You can complain to your local data protection authority. [OPEN QUESTION: if the app is offered in the EU or UK and the developer has no establishment there, Article 27 of the GDPR may require appointing a representative. Consider limiting distribution, or appointing one.]

We won't treat you differently for exercising your rights.

## 15. Changes to this policy

If we change this policy, we'll update the "Last updated" date and post the new version at [PRIVACY POLICY URL]. For material changes, we'll tell you in the app before they take effect, and ask for your consent again where the law requires it.

## 16. Contact

Nicholas Will
Email: cinderandcrown@gmail.com
Mail: [MAILING ADDRESS]

---

### Open questions for this document

1. Publisher: Nicholas Will (individual, matching the Apple Developer account) or transfer to Cinder and Crown LLC.
2. Contact address: cinderandcrown@gmail.com or a dedicated privacy@ address. A mailing address is also needed.
3. Face recognition in the public build: ship, geo-restrict, or remove (section 5).
4. Meta telemetry: opt out (recommended) or disclose (section 4.4).
5. EU/UK distribution and the GDPR Article 27 representative.
6. Retention periods in brackets in section 10.
