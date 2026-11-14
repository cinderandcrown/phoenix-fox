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

## One change only you can make at Apple

The app asks iOS for a higher memory limit so the on-device models are not stopped. Apple's API cannot turn that capability on, so it needs one visit to the developer site:

1. Open [developer.apple.com/account](https://developer.apple.com/account) → **Certificates, Identifiers & Profiles** → **Identifiers**.
2. Open `com.cinderandcrown.phoenixfox`.
3. Tick **Increased Memory Limit** and save.

If this is not on, the "Sign for the App Store" step of the TestFlight workflow fails and names the entitlement.

## Get a build onto the iPhone

1. On GitHub, open **Actions → TestFlight → Run workflow**. Leave **Upload to TestFlight** ticked and run it on `main`.
2. The run archives the app, signs it for the App Store, checks the signed app, asks Apple to validate it, uploads it, and waits until Apple has finished processing. The build number is the run number, so every run is a new build. A run that fails before the upload step has sent nothing to Apple.
3. The run puts the build in an internal testing group named **Phoenix Fox team** and adds the account holder to it. If the summary says it could not add you, open App Store Connect → **TestFlight → Internal Testing → Phoenix Fox team** and add yourself.
4. On the iPhone, install **TestFlight** from the App Store and sign in with the same Apple ID. Phoenix Fox appears there. Install it.

Pushing a tag named `v` plus the app version, such as `v1.0.0`, does the same as step 1. A pull request that touches signing files runs the same workflow without the upload, as a rehearsal.

## Set up the glasses

1. Install **Meta AI** from the App Store, sign in with the account that owns the glasses, and pair the Adventurer glasses there. Phoenix Fox does not replace that pairing.
2. In Meta AI, open **Settings → App Info** (named **About** in some versions) and tap the version number five times. Turn **Developer Mode** on, and leave it on.
3. Open Phoenix Fox. Go to **Settings → Glasses** and tap **Register App**. Meta AI opens, asks you to allow Phoenix Fox, and sends you back to Phoenix Fox.

If you are not sent back, or the Glasses screen still says it is not registered, look at the message under the button. A message from the glasses SDK is shown there as written. The usual causes are Developer Mode being off, or the Meta project not matching the team ID, bundle ID, or universal link above.

The capture light on the glasses is Meta's hardware. Phoenix Fox cannot turn it off and does not try to. The camera runs only when you ask for it.

## Connect your assistants

1. In Phoenix Fox, open **Settings → AI Backend → Assistants**.
2. Leave **Relay address** empty to use the Phoenix Fox relay. Paste the relay token into **Relay token**. The token is kept in the iPhone's Keychain. It is not in this repository and is not a GitHub secret.
3. Tap **Test connection**. A good result saves the address and the token. Any other result says what was wrong: the token, the address, or the network.
4. Tap **Turn on alerts** and allow notifications. This is the only place the app asks. Without it, messages from your assistants are still spoken while the app is open.

## Try it

Put the glasses on with Phoenix Fox open. iOS asks for the microphone and speech recognition the first time. The orange dot at the top of the iPhone screen is on while Jarvis is listening. That is iOS showing that the microphone is in use.

| You say | What should happen |
| --- | --- |
| **Jarvis** | A chime. The app is listening for one request, and stays open for a follow-up until you stop talking. |
| Jarvis, what time is it | The time is spoken. No network and no model are used. |
| Jarvis, ask Indy about the gate | The request goes to Indy through the relay, and Indy's reply is spoken with Indy's name. |
| Jarvis, what do you see | The capture light comes on, one picture is taken, the light goes off, and the answer is spoken. |
| Jarvis, take a picture | The picture is saved to Photos. iOS asks for Photos access the first time. |
| Jarvis, remember this | An encrypted note is kept on the phone. |
| Jarvis, stop | Speech stops. |

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
