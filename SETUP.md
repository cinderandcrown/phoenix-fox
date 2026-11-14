# Phoenix Fox setup

Phoenix Fox is the name on the phone and on the App Store. **Jarvis** is only the wake word inside the app. "Hey Meta" stays Meta's and cannot be replaced.

You do not need a Mac. GitHub Actions compiles and signs the app, and TestFlight installs it on the iPhone.

The glasses under test are Meta Glasses Adventurer: camera, microphones, and speakers, with no lens display. Display glasses and the Neural Band use the same code and stay idle until the glasses report a display.

Nothing in this guide has been run on a real pair of glasses yet. Each step says what should happen, so the first step that does something else is the one to report.

## What is already in place

| Item | State |
| --- | --- |
| Apple team, App ID `com.cinderandcrown.phoenixfox`, App Store Connect app "Phoenix Fox" | Created by the owner. |
| GitHub secrets `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `META_CLIENT_TOKEN` | Set by the owner. |
| Meta Wearables project: camera and microphone, team ID, bundle ID, universal link | Saved by the owner. |
| Universal link `https://phoenix-fox-links.cinderandcrown.workers.dev/dat` | Served by the owner's Cloudflare Worker. The app's Associated Domains entitlement names the same host. |
| Relay `https://phoenix-fox-relay.cinderandcrown.workers.dev` | Deployed by the owner. It is the app's default address. |
| Push Notifications and Associated Domains on the App ID | On. The TestFlight workflow checks both on every run and turns on what is missing. |

## Two changes only you can make at Apple

The TestFlight workflow has run as far as the signing step, and that step needs both of these.

### 1. An App Store Connect key with the Admin role

The build is signed for the App Store by Apple, with a certificate Apple keeps for the team. Apple lets only a key with the **Admin** role use that certificate. The key in the repository secrets has the App Manager role, so the step "Sign for the App Store" stops with "Cloud signing permission error".

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API** → **Team Keys**.
2. Add a key, choose the access **Admin**, and download the `.p8` file. Apple shows it once.
3. In the GitHub repository, open **Settings → Secrets and variables → Actions** and replace `ASC_KEY_ID` with the new Key ID and `ASC_KEY_P8` with the whole file, including the BEGIN and END lines. `ASC_ISSUER_ID` does not change.
4. Revoke the old App Manager key on the same App Store Connect page.

A key's role cannot be edited, which is why this is a new key. An Admin key can also manage users and certificates, so keep it only in the repository secrets.

### 2. The Increased Memory Limit capability

The app asks iOS for a higher memory limit so the on-device models are not stopped. Apple's API cannot turn that capability on.

1. Open [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Open `com.cinderandcrown.phoenixfox`.
3. Tick **Increased Memory Limit** and save.

If it is off, the signing step can stop because the profile Apple makes does not allow that entitlement. The error names it.

## Get a build onto the iPhone

1. On GitHub, open **Actions → TestFlight → Run workflow**. Leave **Upload to TestFlight** ticked and run it on `main`.
2. The run archives the app, signs it for the App Store, checks the signed app, asks Apple to validate it, uploads it, and waits until Apple has finished processing. The build number is the run number, so every run is a new build. A run that fails before the upload step has sent nothing to Apple.
3. The run puts the build in an internal testing group named **Phoenix Fox team** and adds the account holder to it. If the summary says it could not add you, open App Store Connect → **TestFlight → Internal Testing → Phoenix Fox team** and add yourself.
4. On the iPhone, install **TestFlight** from the App Store and sign in with the same Apple ID. Phoenix Fox appears there. Install it.

Pushing a tag named `v` plus the app version, such as `v1.0.0`, does the same as step 1. So does a tag under `testflight/`, such as `testflight/2026-11-14`, which uploads that commit without naming a release. A pull request that touches signing files runs the same workflow without the upload, as a rehearsal.

## Set up the glasses

1. Install **Meta AI** from the App Store, sign in with the account that owns the glasses, and pair the Adventurer glasses there. Phoenix Fox does not replace that pairing.
2. In Meta AI, open **Settings → App Info** (named **About** in some versions) and tap the version number five times. Turn **Developer Mode** on, and leave it on.
3. Open Phoenix Fox. The first time, it walks you through five short steps, and each one can be skipped. On **Connect your glasses**, tap **Open Meta AI**. Meta AI opens, asks you to allow Phoenix Fox, and sends you back to Phoenix Fox. If you skipped that step, tap the glasses chip at the top of the home screen, or go to **Settings → Glasses**, and tap **Register App**.

If Meta AI shows “Internal error”, or you are sent back and Phoenix Fox still says the glasses are not connected, the first-run step and the Glasses screen show the same recovery card: turn Developer Mode off and on again, update Meta AI and the glasses, force-quit Meta AI, and try again. A line under the card says what the glasses toolkit reported, with no secrets. The usual causes are Developer Mode being off, Meta AI below V292, glasses firmware below V128, or the Meta project not matching the team ID, bundle ID, or universal link above.

The capture light on the glasses is Meta's hardware. Phoenix Fox cannot turn it off and does not try to. The camera runs only when you ask for it.

## Connect your assistants

The first-run step **Connect your assistants** takes the relay address and token and tests them. To enter or change them later:

1. In Phoenix Fox, open **Settings → AI Backend → Assistants**, or tap **Connect your assistants** on the home screen.
2. Leave **Relay address** empty to use the Phoenix Fox relay. Paste the relay token into **Relay token**. The token is kept in the iPhone's Keychain. It is not in this repository and is not a GitHub secret.
3. Tap **Test connection**. A good result saves the address and the token. Any other result says what was wrong: the token, the address, or the network.
4. If you did not allow notifications during first run, tap **Turn on alerts** and allow them. Without it, messages from your assistants are still spoken while the app is open.

## Try it

Put the glasses on with Phoenix Fox open. If you skipped the permissions step in first run, iOS asks for the microphone and speech recognition now. The orange dot at the top of the iPhone screen is on while Jarvis is listening. That is iOS showing that the microphone is in use.

The home screen shows what Jarvis is doing in a word or two under the orb: Ready, Listening, Looking, Asking Indy, Replying. Below it is a card for each assistant with what it is doing. A red banner and a red ring around the orb mean the glasses camera is on. [docs/DESIGN.md](docs/DESIGN.md) describes the screen.

| You say | What should happen |
| --- | --- |
| **Jarvis** | A chime. The app is listening for one request, and stays open for a follow-up until you stop talking. |
| Jarvis, what time is it | The time is spoken. No network and no model are used. |
| Jarvis, ask Indy about the gate | Jarvis says "Asking Indy." at once. The request goes to Indy through the relay, Indy's card on the home screen shows the task, and Indy's reply is spoken with Indy's name. |
| go on | After a long answer that ended with "There's more. Say go on.", the next part is spoken. Turn this off with **Short spoken replies** under Assistants. |
| Jarvis, what do you see | The capture light comes on, one picture is taken, the light goes off, and the answer is spoken. |
| Jarvis, take a picture | The picture is saved to Photos. iOS asks for Photos access the first time. |
| Jarvis, remember this | An encrypted note is kept on the phone. |
| Jarvis, stop | Speech stops. A tap on the orb while Jarvis is talking does the same. |

If a reply comes from the phone and not the glasses, the glasses are not the audio route. Check that they show as connected in iOS Bluetooth settings.

If no assistant is set up, Jarvis says so and tells you to open Settings. A request is not dropped in silence.

To try an alert, send one from any machine that has the relay token:

```bash
curl -X POST https://phoenix-fox-relay.cinderandcrown.workers.dev/push \
  -H "Authorization: Bearer $RELAY_TOKEN" \
  -H "Content-Type: application/json" \
  -H "User-Agent: phoenix-fox-test/1.0" \
  -d '{"text":"Gate is open","from_bot":"Driver","priority":"urgent"}'
```

An urgent message interrupts and is spoken at once. A normal one is spoken when the app is quiet. A low one is kept for later and is not spoken when it arrives. With the app open, this works through the inbox without Apple's push service.

## The owner build

A build from the TestFlight workflow is the owner build: every feature starts switched on, and the glasses features Meta still calls beta are allowed. Nothing starts by itself. The camera, a recording, and Guide mode still wait to be asked, Guide mode still reads its safety notice first, and saving a face still asks whether the person agreed.

**Settings → Owner build** has three things: **Glasses limits**, **Workshop**, and **Turn everything on again** for after you have switched things off. What each glasses switch does, and what it costs, is in [docs/GLASSES_SDK.md](docs/GLASSES_SDK.md).

Nothing is for sale in this build. **Settings → Plan** says "Everything is unlocked" and shows the plans a public build could sell, for reading only. The build never asks the App Store for anything. The plan behind it is in [docs/BUSINESS_MODEL.md](docs/BUSINESS_MODEL.md).

Do these once:

1. Open **Settings → Glasses → Glasses limits** and tap **Allow the glasses' microphone**. Meta AI opens and asks. Without it, speech on the glasses stays quiet and everything else works.
2. If the Glasses screen says the glasses need an update, use **Update the glasses** (their software) or **Update the glasses app** (Phoenix Fox's part on the glasses) on that screen.

One thing behaves differently from a standard build. With **Speech on the glasses** on, whenever the phone's microphone is not listening, a single tap on the glasses' touchpad pauses Phoenix Fox's connection and a long press ends it, in place of what those gestures normally do. If you would rather keep them, switch that one off.

None of this has run on glasses yet. These are the checks, with the glasses on:

| Do this | What should happen |
| --- | --- |
| Say **Jarvis**, then double-tap the touchpad while it is answering a question | Jarvis listens again |
| Swipe back on the touchpad while Jarvis is talking | Jarvis stops talking |
| After **Jarvis**, press the capture button once | The light comes on and Jarvis says what it sees |
| After **Jarvis**, press it twice | A picture is saved to Photos at 4032 by 3024 |
| After **Jarvis**, hold it | A note is taken |
| Teach a routine, say **Jarvis, delete my morning routine**, then nod twice | The routine is deleted. Shake your head and it is kept. |
| Shake your head while Jarvis is talking | Jarvis stops talking |
| Say **Jarvis, record a clip**, then stop it | The clip in Photos is 720 by 1280 with the sound of the room |
| Long-press the touchpad while Jarvis is answering | The connection ends and is not reopened until you next say Jarvis |
| **Settings → Glasses** while the camera is on | The Stream row shows the size and frame rate in use |

Speech on the glasses only matters in the moments the phone is not listening, which are hard to stage, so it has no row here.

If one of these fails, switch its switch off under Glasses limits and the rest keep working. With every switch off, this build uses the glasses exactly as a standard build does.

## The workshop

The workshop is ten features built from [docs/INNOVATION_BACKLOG.md](docs/INNOVATION_BACKLOG.md). They are in the owner build only, under **Settings → Owner build → Workshop**, and each has its own switch. In this build they start on.

Two of them are about health. **Ingredient watch** and **Dose guard** are aids. They are not medical devices, they can misread a label, and they read English only. Ingredient watch never says a food is safe: when it finds none of your words it says so, and you still read the label when it matters. Dose guard knows only the doses you told it about.

Before you try them:

1. Open **Workshop → What to look for** and switch on what Ingredient watch should look for. Until you do, "check the ingredients" tells you the list is empty and takes no picture.
2. Open **Workshop → Skills**, pick an example, read what it captures and asks, and add it. Three of the examples name Indy, Rally, and Fire Fox.
3. Place notes ask for location the first time you leave one.

None of this has run on glasses or against your relay. These are the checks, each after saying **Jarvis**:

| Say this | What should happen |
| --- | --- |
| **Start a walk-through at the shop**, then **note the back door sticks**, then **photo flag water under the sink** | Each is confirmed. The capture light comes on for the photo only. |
| **Finish the walk-through**, then **send the walk-through to Indy** | You hear the counts, then Indy's answer. Indy receives the report as text with the photo. The walk-through is under Workshop, Walk-throughs, with a Share button. |
| **Start a tally for the storeroom**, **twelve cases of cups**, **take away two cases of cups**, **how many cases of cups**, **undo**, **finish the tally** | The running count after each: 12, 10, 10, 12, then the summary. Nothing leaves the phone. |
| Hold a food label and say **check the ingredients** | The light comes on. You hear which of your words are on the label, with the words it read, or that none was found after two looks. It never says "safe". |
| Hold a medicine box and say **I'm taking this**, then say it again a minute later | The first is logged with the time. The second says "Wait", how long ago the last one was, and that you can say **log it anyway**. |
| **What have I taken today** | The doses logged today. This turn is not in History. |
| **Ask the council, should I move the launch to Friday** | Every assistant votes. You hear the count, who disagreed, and one reason. No picture is taken. |
| **Ask Indy to find three venues, then Driver to price the travel** | "Indy, then Driver", then a line as it is passed on, then Driver's answer. |
| **Whenever I put my glasses on, say good morning**, then take the glasses off and put them on | "Good morning" within a few seconds of putting them on, at most once in thirty minutes. |
| **Leave a note here: the spare key is in the blue tin**, then **any notes here** | "Note left here", then the note read back. |
| **Price check**, looking at a price tag, after adding that skill | The light comes on and Indy's answer is spoken. |
| **Close the day** | Your main assistant gets today's walk-throughs, tallies, notes, votes, and skills, and answers with a summary. Nothing about medicine or ingredients is in it. |

If one misbehaves, switch it off under Workshop and the rest keep working. **Erase everything the workshop keeps** removes its records from the phone.

## Accessibility

Guide mode, reading, money and label reading, colors, face recognition with consent, live captions, sound alerts, step-by-step tasks, and "what was I doing?" are set under Settings, then Accessibility, and each has a spoken command. Say "Jarvis, what can I say?" to hear them.

Read the safety section of [docs/ACCESSIBILITY.md](docs/ACCESSIBILITY.md) first. Guide mode is an aid and does not replace a cane or a guide dog. The same file has the status of each feature and the eleven checks to run on the glasses.

iOS asks for three more permissions the first time each is needed: location for walking directions and "where am I", notifications for sound alerts if you did not allow them in first run, and Contacts for "set my emergency contact to" a name. To start walking directions with the phone locked, set location for Phoenix Fox to Always in the Settings app.

## Alerts when the app is closed

Alerts that arrive while the app is closed go through Apple's push service, and three things must line up:

- You turned on alerts in the app (above).
- The relay has its push secrets: `APNS_KEY_ID`, `APNS_KEY_P8`, and `APPLE_TEAM_ID`. The owner has set these.
- The relay uses Apple's production push service for a TestFlight build. The relay that is deployed today was set to the sandbox service (`APNS_USE_SANDBOX=true`), which TestFlight builds do not use. The relay pull request fixes this: the app tells the relay which service its token belongs to, and the relay tries the other one if Apple refuses the first. Merge that pull request and run `npx wrangler deploy` from `relay/`.

Once that relay is deployed, **Test connection** in the app also says whether push is set up on the relay. Until then it only confirms the address and the token. The relay's interface is described in [docs/RELAY_API.md](docs/RELAY_API.md).

## What the build contains that is not secret

| Value | Where |
| --- | --- |
| Meta App ID `1651172483404286` | Info.plist `MWDAT` → `MetaAppID` |
| Universal link `https://phoenix-fox-links.cinderandcrown.workers.dev/dat` | Info.plist `MWDAT` → `AppLinkURLScheme`, and the Associated Domains entitlement |
| Bundle ID `com.cinderandcrown.phoenixfox` | Build settings |
| Relay address | `RelayEndpoint.defaultAddress` |

The Meta client token and the Apple team ID are read from GitHub secrets when the build is made. The relay token is typed into the app. None of the three is in the repository.

## If you later have a Mac

`project.yml` is the XcodeGen description. The committed `PhoenixFox.xcodeproj` is what CI builds, and `scripts/xcodeproj_sync.py` keeps its file list in step with the source folders. Before a local build, copy `Config.xcconfig.example` to `Config.xcconfig` and `OpenVision/Config/Config.swift.example` to `OpenVision/Config/Config.swift`, and fill in your team ID. Leave `META_CLIENT_TOKEN` out of git. The scheme is PhoenixFox.

The source folder is still named `OpenVision/` because that is the MIT-licensed project this app started from.
