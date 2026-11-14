# Phoenix Fox Terms of Use (End User License Agreement)

> **Draft prepared for review; have a licensed attorney review before publishing.**
>
> Items in **[brackets]** must be filled in or decided before publishing.

**Effective date:** [DATE]

## Summary

- These terms are a license agreement between you and **Cinder and Crown LLC**, the developer of Phoenix Fox. **They're not with Apple, Google, Meta, or any AI provider.**
- You must be **18 or older**.
- Accessibility features are free. Paid subscriptions cover AI features. **Subscriptions renew automatically until you cancel**, which you can do in your App Store (or Google Play) account settings.
- **Don't use Phoenix Fox to record or identify people secretly, or to spy on anyone.** Follow recording and privacy laws where you are. If you use face recognition, **you're responsible for getting each person's consent** (section 6A).
- AI can be wrong. Don't rely on Phoenix Fox for safety, medical, legal, financial, or emergency decisions. Call 911 in an emergency.
- Texas law governs these terms.

---

## Why we use our own terms instead of Apple's standard EULA

Apple lets developers use Apple's Licensed Application End User License Agreement ("Standard EULA") or their own. We chose **our own terms, which include every minimum term Apple requires** (section 15). The Standard EULA doesn't cover things this app needs: rules against covert recording and unlawful surveillance, the responsibilities that come with face recognition, disclaimers for AI output and accessibility aids, how third-party AI providers fit in, and Texas governing law. (The Standard EULA chooses California law.)

To use these terms, add the published URL in App Store Connect under **App Information > License Agreement**, change `StoreCatalog.termsURL` in `OpenVision/Services/Store/Core/StoreCatalog.swift` from Apple's Standard EULA to that URL, and put the same link in the app description.

---

## 1. Agreement

By downloading or using Phoenix Fox ("the app"), you agree to these Terms of Use and to the [Privacy Policy](PRIVACY_POLICY.md) and [Disclaimers](DISCLAIMERS.md), which are part of these terms. If you don't agree, don't use the app.

"We", "us", and "our" mean **Cinder and Crown LLC**, a Texas limited liability company based in Dallas, Texas, USA. "You" means the person using the app.

## 2. Eligibility

You must be **at least 18 years old** and able to form a binding contract. Don't use the app where it's illegal for you to do so.

## 3. License

We grant you a limited, non-exclusive, non-transferable, revocable license to install and use the app for your personal, non-commercial use, on devices you own or control, as permitted by the Usage Rules in the Apple Media Services Terms and Conditions (or, for Android, the Google Play Terms of Service). That includes use by other accounts in your Family Sharing group where that applies.

You may not: (a) rent, lease, sell, or sublicense the app; (b) use the app to build a competing service by copying its non-open-source materials; (c) remove notices; (d) get around any security or usage limit; or (e) use the app in violation of law.

**Open-source code.** Much of the app's source code is published under the Apache License 2.0 and other open-source licenses listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Those licenses govern that code, and nothing in these terms limits your rights under them. These terms govern your use of the app as distributed through app stores. The names "Phoenix Fox", its logo, and its branding aren't licensed under any open-source license.

## 4. Glasses, platforms, and services you connect

The app works with compatible AI glasses through Meta's Wearables Device Access Toolkit and the Meta AI app. It connects to AI providers (such as xAI, OpenAI, Anthropic, and Google), relays, gateways, and search services **that you choose and set up with your own API keys**. App store versions don't support signing in with a consumer ChatGPT or SuperGrok subscription.

- Those products and services belong to other companies. **Their terms and privacy policies apply** to your use of them, and you're responsible for following them, including their usage policies, age limits, and fees. Any charges from an AI provider for your own key are between you and that provider.
- We don't control those services. We aren't responsible for their availability, content, security, or how they handle your data. A provider or platform may change or stop features, and that can change what the app can do.
- Meta's glasses features depend on Meta's toolkit, firmware, and approval. Some features may be unavailable on some glasses or in some regions.

## 5. Subscriptions and payments

**Free features.** The accessibility suite (including reading, sound alerts, live captions, and guide features), the wake word, and the on-device AI are free and won't be put behind a paywall.

**Paid plans.** Paid subscriptions unlock AI features that cost money to run, as described on the purchase screen. Plan names, what's included, and prices in your currency are shown in the app before you buy. [Today's planned plans: "Own AI" and "Bot Team", monthly or yearly. "Included AI" isn't offered until it has a metered service.]

**Auto-renewal.** Payment is charged to your Apple Account (or Google Play account) when you confirm the purchase. **A subscription renews automatically** for the same length of time at the then-current price **unless you cancel at least 24 hours before the end of the current period.** Your account is charged for the renewal within the 24 hours before the current period ends. You can manage or cancel subscriptions in your account settings on the App Store (iPhone: Settings > [your name] > Subscriptions) or Google Play. Deleting the app doesn't cancel a subscription.

**Free trials and offers.** If a free trial or introductory price is offered, the terms are shown before you accept. Any unused part of a free trial ends when you buy a subscription.

**Price changes.** If a price goes up, Apple or Google will notify you, and ask for your consent where required, before the new price applies.

**Refunds.** Apple and Google handle payments and refunds under their own policies. We can't issue refunds for app-store purchases. Request one from Apple at https://reportaproblem.apple.com, or from Google Play.

**Restore.** Use "Restore purchases" in Settings > Plan to restore a subscription on a new device.

## 6. Acceptable use

Phoenix Fox puts a camera and microphone on your face. You agree to use it lawfully and respectfully. **You won't:**

1. **Record people secretly.** Don't record, stream, caption, transcribe, or photograph anyone in a way that breaks the law, including recording a private conversation without the consent the law requires. (Some states require everyone's consent. See the Privacy Policy, section 8.)
2. **Defeat or cover the glasses' capture light**, or otherwise hide that you're capturing.
3. **Use the app for unlawful surveillance**, stalking, harassment, doxxing, or tracking a person without their consent.
4. **Save anyone's face without their own consent**, or use face recognition where it's unlawful. Delete a saved face when the person asks (see section 6A).
5. **Record in prohibited or private places**, such as restrooms, locker rooms, changing areas, medical settings, schools where recording is barred, courtrooms, or anywhere that posts a no-recording rule.
6. Use the app to make content that's illegal, sexually exploits anyone (especially minors), infringes someone's rights, or deceives people about who made it.
7. Use the app while driving or operating machinery, or in any way that puts you or others in danger.
8. Break the terms or usage policies of Meta, Apple, Google, or any AI provider you connect.
9. Reverse-engineer, attack, overload, or try to get unauthorized access to the app, a relay, or any connected service, except as open-source licenses expressly allow.
10. Use the app for any high-risk purpose where an error could cause death, injury, or serious harm (see section 8).

**Confirmation for actions.** Before Phoenix Fox sends a message, places a call, buys something, or posts anything for you, it asks you to **confirm by voice**. In most cases iOS then shows the message or call for you to send yourself. You're responsible for what you confirm and send.

We may suspend features or end your license if you break this section (section 12).

## 6A. Face recognition: your responsibility

Face recognition is optional, off by default, and works only on your phone. If you turn it on, **you're responsible for how you use it**, and you agree that:

1. **You'll enroll only people who personally agree.** Before you save someone, they must clearly say yes, in their own voice, to Phoenix Fox's consent question. You won't answer for them, pressure them, or enroll anyone who can't understand the request (including children).
2. **You'll get written consent where the law requires it.** Some laws, such as the Illinois Biometric Information Privacy Act (740 ILCS 14/15(b)), require a written release. Where a law like that applies to you or to the person, you'll get that release before enrolling them.
3. **You'll delete on request.** If a saved person asks you to delete their face, or withdraws consent, you'll delete it immediately, by voice or in Settings.
4. **You won't misuse it.** You won't use face recognition to identify strangers, track or monitor people, make decisions about anyone (for example, access, employment, or confronting someone), or for any commercial purpose, and you won't use it where it's unlawful.
5. **You won't defeat the safeguards.** You won't try to extract, export, copy, or share face data, or get around the consent question or automatic deletion.
6. **You'll follow the law.** Biometric privacy laws (including Tex. Bus. & Com. Code § 503.001, 740 ILCS 14, Washington RCW 19.375, and GDPR Article 9) and recording laws may apply to you as the person who decides whom to enroll. Phoenix Fox gives you tools to comply, but it can't make your use lawful for you.

Face data is kept and destroyed on the schedule in the Privacy Policy, section 5.2. You agree to indemnify us for claims arising from your enrollment or use of face data in breach of this section (section 11).

## 7. Your content

"Your content" means what you say, capture, type, or save in the app. You keep all rights to it. You give us no rights to it except as needed to run the features you use on your device. When you send content to an AI provider or other service, you're responsible for having the right to send it, and that service's terms apply to it.

**Feedback.** If you send us ideas or bug reports, you let us use them without owing you anything.

## 8. AI output and other important disclaimers

- **AI can be wrong.** Answers, descriptions, translations, readings of text, money, labels, colors, sounds, directions, and face matches may be inaccurate, incomplete, out of date, or offensive. Check anything important yourself.
- **Not professional advice.** The app doesn't give medical, legal, financial, or safety advice. The medication log and allergen check only repeat what you logged or what text recognition read. They don't say whether something is safe for you.
- **Accessibility aids are assistive only.** Reading, guide, walking directions, sound alerts, and captions can miss things. They don't replace a white cane, guide dog, orientation and mobility training, hearing aids, smoke or carbon monoxide alarms, or your own judgment.
- **Not for emergencies.** Don't rely on the app to call for help. **In an emergency, call 911** (or your local emergency number) directly.
- **Not for driving.** Don't use the app while driving.

More detail is in the [Disclaimers](DISCLAIMERS.md).

## 9. Warranty disclaimer

To the fullest extent the law allows, **the app is provided "as is" and "as available"**, without warranties of any kind, express or implied, including merchantability, fitness for a particular purpose, accuracy, non-infringement, and uninterrupted or error-free operation. Some places don't allow these exclusions, so some may not apply to you. Section 15.4 explains Apple's limited role.

## 10. Limitation of liability

To the fullest extent the law allows:

- We won't be liable for any indirect, incidental, special, consequential, exemplary, or punitive damages, or for lost profits, data, or goodwill, arising from the app, third-party services, AI output, or your content, even if we were told they were possible.
- Our total liability for all claims about the app is limited to **the greater of (a) the amount you paid for the app and subscriptions in the 12 months before the claim, or (b) US $50.**
- Nothing in these terms limits liability that can't be limited by law, such as liability for fraud, or for death or personal injury caused by gross negligence or willful misconduct.

## 11. Indemnity

You agree to defend and hold us harmless from claims by others arising from your misuse of the app or your breach of these terms, including recording, identifying, or surveilling people unlawfully.

## 12. Termination

You can stop using the app at any time by deleting it (and canceling any subscription). We may suspend or end your license if you materially break these terms, or if we stop offering the app. When the license ends, you must stop using the app. Sections 6, 6A, 7-11, 13, 14, and 15 survive termination.

## 13. Changes

We may update these terms. We'll post the new version with a new effective date and, for material changes, tell you in the app before they take effect. If you keep using the app after that, you accept the changes. If you don't agree, stop using the app and cancel your subscription.

## 14. Governing law and disputes

These terms are governed by the **laws of the State of Texas, USA**, without regard to conflict-of-law rules. Any dispute that isn't resolved informally will be brought only in the state or federal courts located in **Dallas County, Texas**, and you and we consent to their jurisdiction. If you're a consumer living outside the United States, you keep any protection your local law gives you that can't be waived by contract. Before filing a claim, please email us so we can try to resolve it within 30 days. [ATTORNEY: decide whether to add an arbitration clause and class-action waiver. They're deliberately left out of this draft.]

## 15. Terms required by Apple (App Store downloads)

These apply when you get the app from Apple's App Store. If they conflict with anything above, this section controls.

**15.1 Acknowledgement.** These terms are between you and us only, not Apple. We, not Apple, are solely responsible for the app and its content. These terms can't give you usage rules for the app that conflict with the Apple Media Services Terms and Conditions as of the date you accept these terms.

**15.2 Scope of license.** The license in section 3 is a non-transferable license to use the app on any Apple-branded products you own or control, as permitted by the Usage Rules in the Apple Media Services Terms and Conditions. The app can also be accessed by other accounts associated with you through Family Sharing or volume purchasing.

**15.3 Maintenance and support.** We're solely responsible for providing any maintenance and support for the app, as stated in these terms or required by law. Apple has no obligation at all to provide maintenance and support for the app.

**15.4 Warranty.** We're solely responsible for any product warranties, whether express or implied by law, to the extent they aren't effectively disclaimed. If the app fails to conform to any applicable warranty, you may notify Apple, and Apple will refund the purchase price for the app (if any) to you. To the maximum extent permitted by law, Apple has no other warranty obligation for the app. Any other claims, losses, liabilities, damages, costs, or expenses from any failure to conform to a warranty are our sole responsibility.

**15.5 Product claims.** We, not Apple, are responsible for addressing any claims by you or any third party relating to the app or your possession or use of it, including: (i) product liability claims; (ii) any claim that the app fails to conform to any applicable legal or regulatory requirement; and (iii) claims under consumer protection, privacy, or similar laws, including in connection with the app's use of the HealthKit and HomeKit frameworks (the app currently uses neither).

**15.6 Intellectual property rights.** If a third party claims that the app, or your possession and use of it, infringes that third party's intellectual property rights, we, not Apple, are solely responsible for the investigation, defense, settlement, and discharge of that claim.

**15.7 Legal compliance.** You represent and warrant that (i) you're not located in a country that is subject to a U.S. Government embargo, or that the U.S. Government has designated as a "terrorist supporting" country; and (ii) you're not listed on any U.S. Government list of prohibited or restricted parties.

**15.8 Developer name and address.** Questions, complaints, or claims about the app go to: **Cinder and Crown LLC**, [LLC MAILING ADDRESS — TO PROVIDE], email **privacy@cinderandcrown.com** (being set up), phone [PHONE NUMBER — TO PROVIDE, OR STATE THAT EMAIL IS THE SUPPORT CHANNEL. ATTORNEY TO CONFIRM].

**15.9 Third-party terms.** You must comply with applicable third-party terms when using the app. For example, you must not violate your wireless data service agreement, or the terms of Meta, or of any AI provider you connect.

**15.10 Third-party beneficiary.** Apple and Apple's subsidiaries are third-party beneficiaries of these terms. Once you accept these terms, Apple will have the right (and will be deemed to have accepted the right) to enforce them against you as a third-party beneficiary.

## 16. Google Play downloads (future Android app)

If you get the app from Google Play, Google isn't a party to these terms and has no responsibility for the app. Google Play's Terms of Service and payment policies apply to purchases made through Google Play.

## 17. General

These terms, the Privacy Policy, and the Disclaimers are the whole agreement between you and us about the app. If any part is found unenforceable, the rest stays in effect. If we don't enforce a term, that isn't a waiver. You can't transfer these terms. We may transfer them to a successor, such as in a merger or sale of the business. Export laws: you won't export or use the app in violation of U.S. export laws.

## 18. Contact

Cinder and Crown LLC, [LLC MAILING ADDRESS — TO PROVIDE], privacy@cinderandcrown.com
