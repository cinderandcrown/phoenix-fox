# Business model

The goal is to add to people's lives and to get paid for it. This page says what is free, what is sold, what each feature costs to run, and what is left after Apple and the model makers are paid.

**Nothing is on sale.** This is a plan. The subscription code is in the app and is switched off. The owner's TestFlight build has everything unlocked and never asks the App Store for anything.

**How to read the numbers.**

- A **price** was read from the vendor's own page on 14 November 2026 and has a link beside it.
- Everything else is an **assumption** and is listed under [Assumptions](#assumptions): how many tokens a question uses, how often somebody asks, what the plans cost.
- **Nothing has been measured.** The app has not run on a phone, and no bill has been paid. The first month of real use should replace the assumptions.
- There is no estimate here of how many people will subscribe. Nobody has data for that. The page gives the number of subscribers that covers the fixed costs, and stops there.

The tables between `cost-model` marks are written by [`scripts/cost_model.py`](../scripts/cost_model.py). Change a price or an assumption there, run `python3 scripts/cost_model.py --write docs/BUSINESS_MODEL.md`, and the tables follow. A test fails if this page and the script disagree, or if a plan's allowance stops leaving the margin promised below.

## The short version

1. **Everything that runs on the phone is free, for good.** That is the whole accessibility suite, the wake word, and questions answered by the model on the phone. It costs Cinder & Crown nothing for each use, so there is no reason to charge for it and no cost that could later force a charge.
2. **Own AI** is the bring-your-own tier: cloud models with the subscriber's own key. The model maker bills the subscriber. With the cheapest models that bill is about 16 cents a month for typical use.
3. **Included AI** is the no-setup tier: Cinder & Crown pays for the model, inside a monthly allowance. It needs a metered service that is not built, so the app does not offer it yet.
4. **Bot Team** is the premium tier: more than one assistant, by name, and all hands.
5. At the proposed monthly prices and allowances, a subscriber who uses every bit of an allowance still leaves 70% or more of what Apple pays out, and 54% or more at the yearly prices. That holds only if hosted turns go to the cheapest capable model. Sent to the models the app asks for by default today, the same allowance would leave 16% to 74%.
6. Three things were found while doing the arithmetic and are worth more than the plan itself: the app's default fast models are no longer the cheap ones, a hosted relay built on long polls would cost about $4 a month for each subscriber, and photos would have left the phone at up to nine times the intended pixel count. The last one is fixed in this change.

## What is free, and why

The free plan is not a trial. It holds:

- The whole accessibility suite in [ACCESSIBILITY.md](ACCESSIBILITY.md): reading, money, colors, labels, Guide mode, walking directions, captions, sound alerts, task steps, and the emergency contact call.
- The wake word, hearing the sentence, and the spoken reply.
- Questions answered by the model on the phone.

All of that runs on the phone with Apple's frameworks or the on-device model. Each use costs nothing, so a million free users cost the same as one.

Two rules are built into the code, not only written here:

- **The accessibility suite is never checked against a plan.** In a spoken turn it is offered the sentence first, and "stop" is handled next. The plan is checked only after both. A test pins the wording of every refusal so that it always says what still works.
- **A brain on the phone needs no plan.** `AIBackendType.paidFeature` is `nil` for the two on-device brains.

Four accessibility features can reach a cloud model when the phone cannot answer by itself: a described scene, a "find", Guide mode's hazard check, and suggested task steps. The three that look at a photo try the model on the phone first. All four use the wearer's own xAI key, and only when one is set. That is not gated by a plan either. A free user with a key pays xAI about a third of a cent for each, and Guide mode stops asking after sixty checks in a session.

That leaves one gap. A free user with no key, on a phone that cannot run the on-device model, gets a plain list from the phone's detectors in place of a described scene. Two ways to close it, neither built:

<!-- cost-model:free -->
| Free described scenes, if they are ever hosted | Figure |
| --- | --- |
| 10 described scenes a day for a month, on `gpt-6-luna` | $0.075 |
| Free users at that rate paid for by one Included AI subscription, before its own costs | 113 |
<!-- /cost-model:free -->

- **Host a small daily allowance of described scenes for everyone.** The table above is what that would cost. It needs the same metered service as Included AI.
- **Apple's Private Cloud Compute.** Apple's [developer page](https://developer.apple.com/private-cloud-compute/) says developers in the Small Business Program whose apps have fewer than two million first-time downloads can use Apple's larger models on Private Cloud Compute with no cloud API cost, on devices that run Apple Intelligence, with a daily limit for each user. It needs an entitlement from Apple. That page was read; the API itself was not tried, and whether it accepts a photo was not checked. Worth evaluating before paying for a hosted free allowance.

## The plans

<!-- cost-model:plans -->
| Plan | A month | A year | Kept from a month at 15% | Kept from a month at 30% | Hosted allowance a month |
| --- | --- | --- | --- | --- | --- |
| Free | $0 | $0 | $0 | $0 | None |
| Own AI | $2.99 | $24.99 | $2.54 | $2.09 | None needed |
| Included AI | $9.99 | $79.99 | $8.49 | $6.99 | 2,400 questions and 600 looks |
| Bot Team | $19.99 | $159.99 | $16.99 | $13.99 | 2,400 questions and 600 looks, 1,000 assistant turns |
<!-- /cost-model:plans -->

"Kept" is the price less Apple's commission, before any cost. The prices and allowances are proposals for the owner to decide. They are not market research.

Each plan holds everything in the plans below it.

| Plan | What it adds | What it costs Cinder & Crown for each use | Does the app's code cover it today? |
| --- | --- | --- | --- |
| Free | The accessibility suite, the wake word, the model on the phone | Nothing | Yes |
| Own AI | Grok, Claude, OpenAI, or Gemini with the subscriber's own key. Live voice and video. One assistant over the subscriber's own relay. | Nothing. The model maker bills the subscriber. | Yes |
| Included AI | Questions and looks with no key to set up, inside a monthly allowance | The model, paid by Cinder & Crown | No. It needs a metered service. |
| Bot Team | More than one assistant, by name, and all hands | Nothing while the subscriber runs the assistants and relay. The model and relay, if Cinder & Crown hosts them. | Yes for a subscriber's own assistants. No for hosted ones. |

So there are two stages.

**Stage one, which the app's code can enforce today:** Free, Own AI, and Bot Team, with the subscriber's own keys, assistants, and relay. Cinder & Crown hosts nothing, so the cost for each use is zero and the only costs are the fixed ones.

**Stage two, which needs a service that does not exist:** Included AI, and a hosted relay and assistants for Bot Team. The margins below are for this stage. `StoreCatalog.hostedAIReady` is `false`, which keeps Included AI off the shelf.

Past an allowance, a subscriber must not be cut off. The design is that the turn goes to their own key if they have one, and otherwise to the model on the phone. The accessibility suite is not part of any allowance.

Two decisions are the owner's to make, and the code makes each a one-line change:

- **Whether bring-your-own should cost anything.** It costs nothing to serve, and the code is open, so anyone can build the app without the check. The case for charging a little is that it pays for the signed build, the updates, and the work of keeping four vendors' interfaces current. The case against is that a free bring-your-own tier is simpler to explain. To make it free, point `PaidFeature.ownKeyAI.plan` at `.free`.
- **The prices.** They live in App Store Connect, not in the code. The app shows whatever the App Store returns.

## What each thing costs

### Prices

<!-- cost-model:prices -->
| Model | Input, per million tokens | Output, per million tokens | Used for | Source |
| --- | --- | --- | --- | --- |
| `grok-4.3` | $1.25 | $2.50 | Grok's default in the app (`grok-4.20-non-reasoning`, the same price), and an assistant's turn | [xai](https://docs.x.ai/docs/models) |
| `claude-haiku-4-5` | $1.00 | $5.00 | Claude's default in the app | [anthropic](https://docs.anthropic.com/en/docs/about-claude/pricing) |
| `gpt-4o-mini` | $0.15 | $0.60 | OpenAI's default in the app | [openai](https://platform.openai.com/docs/pricing) |
| `gpt-6-luna` | $0.10 | $0.50 | Cheapest route found | [openai](https://platform.openai.com/docs/pricing) |
| `claude-haiku-5.5` | $0.10 | $0.50 | Cheapest route found | [anthropic](https://docs.anthropic.com/en/docs/about-claude/pricing) |
<!-- /cost-model:prices -->

The app's default for Grok is `grok-4.20-non-reasoning`, which xAI lists at the same price as `grok-4.3`. Its fallback when that setting is empty, `grok-4-fast-non-reasoning`, was [retired on 15 May 2026](https://docs.x.ai/developers/migration/may-15-retirement) and is answered by `grok-4.3` at `grok-4.3`'s price. One row prices both.

The app can also sign in with a SuperGrok or ChatGPT subscription in place of a key. A subscriber who does that pays the vendor's subscription and no charge for each use. Those subscriptions' prices were not read and are not in any figure here.

### One question and one look

A "question" is one spoken sentence answered in words. A "look" is the same with one photo from the glasses.

<!-- cost-model:per-use -->
| Model | One spoken question | Tokens for one photo | One look |
| --- | --- | --- | --- |
| `grok-4.3` | $0.0022 | 768 | $0.0031 |
| `claude-haiku-4-5` | $0.0021 | 448 | $0.0025 |
| `gpt-4o-mini` | $0.0003 | 14,167 | $0.0024 |
| `gpt-6-luna` | $0.00021 | 404 | $0.00025 |
| `claude-haiku-5.5` | $0.00021 | 448 | $0.00025 |
<!-- /cost-model:per-use -->

The photo column is each vendor's published rule applied to a 432 by 768 photo:

- Anthropic counts one token for each 28-pixel square ([vision guide](https://docs.anthropic.com/en/docs/build-with-claude/vision)).
- OpenAI's newer models count 32-pixel squares times a multiplier. `gpt-4o-mini` uses the older rule, 2,833 tokens plus 5,667 for each 512-pixel tile, which is why the same photo costs it thirty-five times as many tokens as it costs `gpt-6-luna` ([images guide](https://platform.openai.com/docs/guides/images-vision)).
- xAI's page no longer gives a rule. The figure uses its earlier one and is an assumption.

### Every feature

<!-- cost-model:features -->
| What happens | Route | Who is billed | Cost |
| --- | --- | --- | --- |
| Wake word, hearing the sentence, speaking the reply | On the phone | Nobody | $0 |
| Reading, money, colors, labels, Guide mode callouts, captions, sound alerts, task steps | On the phone | Nobody | $0 |
| A question to the on-device model | On the phone | Nobody | $0 |
| A question to a cloud model | `gpt-6-luna` to `grok-4.3` | The key's owner, or the plan | $0.00021 to $0.0022 |
| One look, or a described scene with no on-device model | `gpt-6-luna` to `grok-4.3` | The key's owner, or the plan | $0.00025 to $0.0031 |
| Guide mode's cloud hazard checks, a whole session at its limit of 60 | `grok-4.3`, with the wearer's own key | The key's owner | at most $0.19 |
| A task for one assistant | `grok-4.3`, 3,000 tokens in and 300 out | Whoever runs the assistant | $0.0045 |
| All hands, or a council of 4 | `grok-4.3`, once for each assistant | Whoever runs the assistants | $0.018 |
| An hour of waiting for alerts on a relay, as built | Cloudflare Durable Object, long poll | Whoever runs the relay | $0.0056 |
| A push alert | Apple Push Notification service | Nobody | $0 |
| A minute of live voice and video | Gemini 3.8 Live, at its per-minute prices | The key's owner | $0.012 |
| A minute of live voice | xAI voice | The key's owner | $0.08 |
<!-- /cost-model:features -->

Notes on the rows:

- **Live voice and video.** The app asks for Gemini 2.5 Flash native audio, which Google prices by the token: $3.00 a million tokens in and $12.00 a million out, at 25 tokens for each second of audio ([Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)). That is $0.0045 for a minute of listening, and $0.018 for a minute of speaking if speech is counted at the same rate. The token rate for video was not found, so the row uses the per-minute prices Google publishes for Gemini 3.8 Live ($0.005 to listen, $0.002 to watch, $0.018 to speak), which are close to those. OpenAI's realtime model is priced by the audio token too ($32 in and $64 out a million) and is not in the table, because its tokens-per-minute rate was not read.
- **Voices.** The built-in voice and the on-device neural voice cost nothing. A cloud voice is billed to the subscriber's own key (xAI lists $15 for a million characters). No plan includes a cloud voice.
- **Push alerts** go through Apple's push service, which has no charge for each message.
- **An assistant task** is priced as if the assistant ran on `grok-4.3`. For the owner's own team, the owner's bill is whatever his Grok Bots actually use; this row is a stand-in for it.

### How a turn is routed

Cost is mostly a matter of where a sentence goes. The order is the one the app already follows:

| A sentence that is | Goes to | Cost |
| --- | --- | --- |
| Silence, or speech without the wake word | Nowhere. The wake word and voice detection run on the phone. | $0 |
| A reading, money, color, label, caption, or guidance command | The accessibility suite, on the phone | $0 |
| A question, with an on-device brain chosen | The model on the phone | $0 |
| A short question, with a cloud brain chosen | That vendor's fast model | A question |
| "What am I looking at" | One photo, shrunk to 768 pixels on its long edge, to the fast model. The camera goes off again. | A look |
| A task, a note, or a named assistant | The relay, to that assistant | An assistant task |
| "All hands" | The relay, once for each assistant | All hands |
| Guide mode's hazard check | The on-device model first. A cloud model only when the scene has really changed, no more than once in twelve seconds, and at most sixty times in a session. | $0, or a look |

A hosted plan would add one rule on top: every hosted turn goes to the cheapest model that can do the job, and a dearer model is used only when the cheap one fails. The margin table below shows why that rule is not optional.

## What a subscriber with their own key pays

Three kinds of user, all assumed:

<!-- cost-model:usage -->
| Use | Questions a day | Looks a day | Assistant tasks a day | All hands a day |
| --- | --- | --- | --- | --- |
| Light | 5 | 1 | 3 | 0 |
| Typical | 20 | 5 | 15 | 1 |
| Heavy | 60 | 20 | 40 | 2 |
<!-- /cost-model:usage -->

What each pays the model maker in a month, for questions and looks:

<!-- cost-model:own-key -->
| Model | Light month | Typical month | Heavy month |
| --- | --- | --- | --- |
| `grok-4.3` | $0.42 | $1.78 | $5.80 |
| `claude-haiku-4-5` | $0.39 | $1.64 | $5.31 |
| `gpt-4o-mini` | $0.12 | $0.54 | $1.99 |
| `gpt-6-luna` | $0.039 | $0.16 | $0.53 |
| `claude-haiku-5.5` | $0.039 | $0.16 | $0.53 |
<!-- /cost-model:own-key -->

So the whole cost of Own AI to a typical subscriber is the plan plus somewhere between 16 cents and $1.78 a month, depending on the model.

### Finding: the default fast models are not the cheap ones any more

The three models the app asks for by default were a cheap choice when they were picked. On the prices read for this page:

- Grok's default costs the same as `grok-4.3`. The only cheaper model xAI lists is its coding model. A typical month costs about eleven times what it would on the cheapest models in the table.
- `claude-haiku-4-5` costs ten times `claude-haiku-5.5` for each token.
- `gpt-4o-mini` is cheap for words, but its photo rule makes one look cost almost ten times a look on `gpt-6-luna`.

The defaults are in `InstantModels` in `BrainCatalog.swift`, `GrokService.defaultModel`, and `AppSettings`. They were left alone in this change, because a model name cannot be tested without a key and a phone, and a wrong name fails every turn. Changing the Claude and OpenAI defaults is the cheapest saving on this page, and should be the first thing tried on a real device. For Grok there is no cheaper chat model to change to, so a subscriber who wants the lowest bill should pick another vendor for quick questions and keep Grok for the assistants.

### Finding: photos would have left the phone too large

`ImageBudget` shrank a photo to 768 points on its long edge and then drew it at the screen's scale, which is two or three on an iPhone. At three, a 720 by 1280 frame from the glasses would leave the phone at 1,296 by 2,304 pixels, which is larger than it started. Vendors charge by the pixel, up to their own limits. It now draws one pixel for each point. A test written for the simulator checks the size; it has not run yet. Every "look" figure on this page assumes the fixed size.

## What a hosted subscriber would cost

This is stage two. Hosted turns go to `gpt-6-luna`. Hosted assistant turns go to `grok-4.3` through a hosted relay.

<!-- cost-model:margins -->
| Plan | Light: cost, margin | Typical: cost, margin | Heavy: cost, margin | Whole allowance: cost, margin | Whole allowance, yearly price | Whole allowance, 30% commission |
| --- | --- | --- | --- | --- | --- | --- |
| Own AI | $0, 100% | $0, 100% | $0, 100% | $0, 100% | 100% | 100% |
| Included AI | $0.039, over 99% | $0.16, 98% | $0.53, 94% | $0.65, 92% | 88% | 91% |
| Bot Team | $0.44, 97% | $2.73, 84% | $5.03, 70% | $5.16, 70% | 54% | 63% |
<!-- /cost-model:margins -->

Margin is what is left of Apple's payout after the model and relay are paid, at the 15% commission unless the column says otherwise. It leaves out the fixed costs, tax, refunds, and the owner's time.

### Targets

| Target | Why |
| --- | --- |
| At least 80% on a typical subscriber | The room that pays for everything not counted here |
| At least 60% on a subscriber who uses a whole allowance, at the monthly price | The allowance, not a heavy user, sets the worst case |
| At least 40% on the same subscriber at the yearly price | A yearly discount must not turn the heaviest users into a loss |
| Above zero on the same subscriber at Apple's 30% commission | The plan must survive losing the Small Business Program rate |

The script checks all four for every plan and fails when one is missed.

### Routing decides the margin

<!-- cost-model:routing -->
| Every hosted turn sent to | Whole allowance costs | Margin on Included AI |
| --- | --- | --- |
| `gpt-6-luna` | $0.65 | 92% |
| `gpt-4o-mini` | $2.17 | 74% |
| `claude-haiku-4-5` | $6.57 | 23% |
| `grok-4.3` | $7.10 | 16% |
<!-- /cost-model:routing -->

The same allowance, on the same plan, at the same price. Only the model changes.

### Finding: the relay must not wait on long polls if it is hosted

The owner's relay is one Durable Object for one person. It is not built to hold many subscribers: there is one token and one object. A hosted relay needs an object for each subscriber, a token for each, and a check of the subscription on the server.

It also needs to wait differently. Cloudflare bills a Durable Object for its memory for every second it is awake, and a request that is waiting for a reply keeps it awake ([Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/)). The phone's long poll, and any assistant that polls for work, do exactly that.

<!-- cost-model:relay -->
| A hosted relay for one subscriber, for a month | Cloudflare cost |
| --- | --- |
| The phone waits with a long poll two hours a day | $0.34 |
| The phone waits with a long poll all day and night | $4.06 |
| One assistant polls all day and night, with no webhook | $4.06 |
| 4 assistants poll all day and night | $16.23 |
| The same waits on hibernating WebSockets and webhooks, 1,000 turns | $0.0049 |
<!-- /cost-model:relay -->

Cloudflare does not bill a WebSocket that uses its hibernation interface while it is idle, and the webhook delivery added in [RELAY_API.md](RELAY_API.md) removes the assistants' polling. The Bot Team margins above assume both. For the owner's own relay none of this matters: Cloudflare's plan includes far more than one person uses, and those included amounts are left out of every figure here, which makes the figures a little high.

## Fixed costs

<!-- cost-model:fixed -->
| Fixed cost a year | Amount | Source |
| --- | --- | --- |
| Apple Developer Program | $99.00 | [apple-membership](https://developer.apple.com/programs/whats-included/) |
| Cloudflare Workers Paid, twelve months | $60.00 | [cloudflare](https://developers.cloudflare.com/workers/platform/pricing/) |
| Total | $159.00 |  |
| Own AI subscribers, typical use, that cover it | 6 |  |
| Included AI subscribers, typical use, that cover it | 2 |  |
| Bot Team subscribers, typical use, that cover it | 1 |  |
<!-- /cost-model:fixed -->

The Cloudflare line is only needed once something is hosted. Not counted: a domain, the owner's time, tax, and legal review of the privacy policy and terms.

## What Apple takes

- **15%** in the App Store Small Business Program, which is for developers who earned up to $1 million in proceeds in the prior year, and for developers new to the store ([Apple](https://developer.apple.com/app-store/small-business-program/)). Enrolling is an application to Apple. Every figure here uses 15% unless it says 30%.
- **30%** otherwise, falling to 15% for a subscriber after their first year of paid service ([Apple](https://developer.apple.com/app-store/subscriptions/)).
- **$99 a year** for the Apple Developer Program ([Apple](https://developer.apple.com/programs/whats-included/)).

Apple's [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) set the shape of the plans:

- 3.1.1: features unlocked inside the app are sold through in-app purchase. That is why this uses StoreKit and not a web checkout.
- 3.1.2(a): a subscription must give ongoing value, last at least seven days, and work on all of the subscriber's devices. The plans follow the Apple Account, not the phone.
- 3.1.2(c): the app must say clearly what the subscriber gets for the price. The Plan screen lists it for each plan, with the renewal terms and links to the terms and privacy policy.
- 5.1.1(i): the app needs a privacy policy, linked inside it. **There is not one yet.** See below.

Those are this page's reading of the guidelines, not a ruling. App Review decides.

## What others charge

Only what was read from each company's own page. None of these is the same product, and none is a forecast for this one.

| Product | What its page says | Source |
| --- | --- | --- |
| Be My Eyes | "Free and unlimited calls" to volunteers | [bemyeyes.com](https://www.bemyeyes.com/) |
| Aira | Paid plans for a trained human agent from $26 a month for 20 minutes to $1,160 a month for 880 minutes. Its AI feature is free. | [aira.io/subscriptions](https://aira.io/subscriptions/), which says it was updated on 1 March 2026 |
| Envision Glasses | $1,899, $2,499, or $3,499 for the glasses with the software, and $200 a year for feature updates | [letsenvision.com](https://www.letsenvision.com/glasses/home). Read from a search result's excerpt of that page, not from the page. |

What that supports, and no more: the best-known tool for blind users is free, AI description is free in at least one paid service, and people do pay for dedicated hardware and for human help. It is a reason to keep the accessibility suite free. It says nothing about how many people would pay for cloud models or an assistant team on glasses.

The World Health Organization's fact sheet says at least 2.2 billion people have a near or distance vision impairment ([WHO](https://www.who.int/news-room/fact-sheets/detail/blindness-and-visual-impairment), read from a search result's excerpt; the page itself timed out). That is the size of the need. It is not a market size for this app, which needs an iPhone and a pair of Meta glasses, and no figure for that overlap was found.

## The subscription code in the app

It uses StoreKit 2. Nothing in it has been compiled by Xcode or run against the App Store yet. See [How it was checked](#how-it-was-checked).

| Piece | Where | What it does |
| --- | --- | --- |
| The plans and what each unlocks | `Services/Store/Core/Plan.swift` | `Plan`, `PaidFeature`, the spoken refusals, and which brains need a plan |
| The catalog and the switch | `Services/Store/Core/StoreCatalog.swift` | The six product identifiers, which plans are on the shelf, and `StoreSwitch`, which decides whether a build sells anything |
| The App Store side | `Services/Store/SubscriptionStore.swift` | Reads what a person holds from the App Store's signed transactions, listens for renewals and refunds, loads prices |
| The screen | `Views/Settings/PlanView.swift` | Settings, then Plan. What each plan holds, buy, restore, manage or cancel, the renewal terms |
| The gates | `VoiceAgentViewModel.sendCommand`, `startLiveVideoMode`, and `FastModeRouter` | A cloud brain needs Own AI. A second assistant or all hands needs Bot Team. |

### When a build sells

`StoreSwitch.isOn` is true only when all three of these hold:

1. The build is not the owner's build.
2. The build setting `PHOENIX_FOX_STORE` is `YES`. It is `NO` in the project.
3. The selling screen has everything it must show. Today it lacks a privacy policy, so the answer is no even with the setting on. A test pins that.

When the answer is no, `Access.everything` is used: every feature works, the Plan screen says so, and StoreKit is never called.

### The owner's TestFlight build

The TestFlight workflow passes `PHOENIX_FOX_OWNER_BUILD=YES` and `PHOENIX_FOX_STORE=NO`. Either one alone keeps the store off. `scripts/check_signed_app.py`, which runs on the signed app before upload, fails if an owner build ever asks to sell, and prints which way the store is set.

### Testing purchases, later

Apple's [TestFlight page](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/) says in-app purchases in a TestFlight build use the sandbox, cost nothing, and renew on a shortened schedule. So the store can be tried in a second TestFlight build with `PHOENIX_FOX_OWNER_BUILD=NO` and `PHOENIX_FOX_STORE=YES` once the products exist. There is no StoreKit test file in the project, because making and running one needs Xcode on a Mac.

### What the check on the phone is good for

StoreKit verifies Apple's signature on each transaction on the phone. That is enough to unlock something that runs on the phone or on the subscriber's own key, where the only thing lost to a cheat is the plan's price, and the code is open in any case. It is not enough for anything Cinder & Crown pays for. A hosted model or relay must check the subscription again on its own server before it spends money. Apple provides a server interface and server notifications for that; none of it is built.

## Before anything is sold

In order. The first block is all that stage one needs.

**Outside the owner's control**

1. Meta has to allow the app into the public App Store. It does not today. See [APP_STORE_PLAN.md](APP_STORE_PLAN.md). Until then the only way to reach people is TestFlight, where purchases are sandbox purchases and nobody pays.

**For the owner**

2. Decide the prices, and whether bring-your-own is paid or free.
3. Publish a privacy policy and put its address in `StoreCatalog.privacyURL`. The terms link points at Apple's standard licence; replace it if Cinder & Crown writes its own.
4. In App Store Connect: sign the Paid Applications agreement, add bank and tax details, and enroll in the Small Business Program.
5. In App Store Connect: create a subscription group named "Phoenix Fox plans" with Bot Team as the highest level, then Included AI, then Own AI, and these six products:
   - `com.cinderandcrown.phoenixfox.plan.ownai.monthly` and `.yearly`
   - `com.cinderandcrown.phoenixfox.plan.includedai.monthly` and `.yearly`
   - `com.cinderandcrown.phoenixfox.plan.botteam.monthly` and `.yearly`

**In the code**

6. Give a new free user a working start. Partly done: first run now ends on the AI built into the phone when no relay and no other AI is set up and the phone has Apple Intelligence. What is left: the setting's default is still "Your assistants", so someone who never sees first run, or whose phone has no Apple Intelligence, still starts with a brain that needs a relay, and a session will not start with an unconfigured brain. A public build should default to the on-device brain and offer the downloadable local model where Apple Intelligence is missing.
7. Change the default fast models, after trying the new names on a phone.
8. Build a build for sale: `PHOENIX_FOX_OWNER_BUILD=NO`, `PHOENIX_FOX_STORE=YES`. The workshop features are owner-build only and stay out of it; the council and the relay race among them belong to Bot Team when they leave the workshop.

**For stage two only**

9. A metered gateway for hosted models: an account for each subscriber, the subscription checked on the server, the allowance counted, and the cheapest-model rule enforced.
10. A hosted relay for many subscribers: an object and a token for each, hibernating WebSockets in place of long polls, webhooks for assistants.
11. Set `StoreCatalog.hostedAIReady` to `true`.

## Assumptions

Every one of these is a guess to be replaced by a measurement. Each is a named constant in `scripts/cost_model.py`.

| Assumption | Value | Where it comes from |
| --- | --- | --- |
| Tokens into a model for one question | 1,500 | The persona, the tool list, and up to eight earlier messages. Not measured. |
| Tokens out for one answer | 120 | The persona asks for one to three short sentences. The app caps a reply at 300 or 400 tokens, depending on the vendor. Not measured. |
| A photo sent to a model | 432 by 768 pixels | A 720 by 1280 frame held to 768 on its long edge by `ImageBudget`. A still photo has a different shape and a similar size. |
| Photo tokens on xAI | 768 | xAI's earlier published rule. Its page gives none now. |
| An assistant turn | 3,000 tokens in, 300 out, on `grok-4.3` | A guess. An assistant carries its own instructions, memory, and tools. |
| Assistants in a team | 4 | The owner's team |
| Light, typical, and heavy use | The usage table above | Guesses. There are no users yet. |
| Days in a month | 30 | |
| The hosted model | `gpt-6-luna` | The cheapest model found with image input. Whether its answers are good enough was not tested. |
| A hosted relay turn | 4 requests and 2 seconds awake | A guess at a relay that hibernates |
| Share of a live conversation the model spends speaking | 30% | A guess |
| Plan prices and allowances | The plans table above | Proposals |
| Free described scenes, if hosted | 10 a day | A proposal |
| Apple's commission | 15% | Assumes enrollment in the Small Business Program |

Left out on purpose, and each would lower the margins a little or raise them a little: sales tax and VAT, prices in other countries, refunds and failed renewals, vendors' discounts for repeated prompts, Cloudflare's included amounts, and the request charge for a hosted gateway, which is under a tenth of a cent a month for each subscriber at these allowances.

## How it was checked

- **The arithmetic** is tested: each vendor's photo rule against the examples on the vendor's page, a question worked by hand, the margin targets, and that this page holds the script's current tables. The tests also check the script against the app: the plan names, the default models, the photo size, and the relay's wait.
- **The plan rules** have unit tests that run on Linux: the order of the plans, what each unlocks, the product identifiers, that the owner build never sells, that nothing is sold while the selling screen is incomplete, and that on-device brains need no plan.
- **`SubscriptionStore`** was type-checked on Linux under strict concurrency against hand-written stand-ins for StoreKit's types. That shows the code is consistent with itself. It does not show that it matches Apple's StoreKit, and it has never talked to the App Store.
- **The Plan screen and the gates in the voice turn** were only parsed. SwiftUI cannot be type-checked on Linux.
- **CI has not run on this change.** GitHub Actions is not starting jobs on the repository until its billing is fixed.

## Sources

All read on 14 November 2026 unless a row above says otherwise.

- xAI models and prices: <https://docs.x.ai/docs/models>
- xAI retired model names: <https://docs.x.ai/developers/migration/may-15-retirement>
- OpenAI prices: <https://platform.openai.com/docs/pricing>
- OpenAI image tokens: <https://platform.openai.com/docs/guides/images-vision>
- Anthropic prices: <https://docs.anthropic.com/en/docs/about-claude/pricing>
- Anthropic image tokens: <https://docs.anthropic.com/en/docs/build-with-claude/vision>
- Google Gemini prices: <https://ai.google.dev/gemini-api/docs/pricing>
- Cloudflare Workers and Durable Objects prices: <https://developers.cloudflare.com/workers/platform/pricing/>
- Apple Small Business Program: <https://developer.apple.com/app-store/small-business-program/>
- Apple subscriptions and commission: <https://developer.apple.com/app-store/subscriptions/>
- Apple Developer Program: <https://developer.apple.com/programs/whats-included/>
- Apple App Review Guidelines: <https://developer.apple.com/app-store/review/guidelines/>
- Apple, testing subscriptions in TestFlight: <https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/>
- Apple Private Cloud Compute for developers: <https://developer.apple.com/private-cloud-compute/>
- Aira plans: <https://aira.io/subscriptions/>
- Be My Eyes: <https://www.bemyeyes.com/>
- Envision Glasses: <https://www.letsenvision.com/glasses/home>
- World Health Organization, blindness and vision impairment: <https://www.who.int/news-room/fact-sheets/detail/blindness-and-visual-impairment>
