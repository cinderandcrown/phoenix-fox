# Phoenix Fox setup

Phoenix Fox is the name on the phone and on the App Store. **Jarvis** is only the wake word. You do not need a Mac. GitHub Actions is the compiler. TestFlight installs the app on the iPhone.

The v1 test is Meta Glasses Adventurer: displayless, camera, mic, and speaker. Meta Ray-Ban Display and the Neural Band are in the code and stay idle until the glasses report a display.

## What you do on the iPhone

Do these in order. The glasses steps need the Meta AI app. The Phoenix Fox steps need a TestFlight build, which waits on the secrets below.

1. Install **Meta AI** from the App Store and sign in with the account that owns the glasses.
2. In Meta AI, open **Settings → About** and tap the version number 5 times. Turn **Developer Mode** on. Pair the Adventurer glasses in Meta AI the way you normally would. The hardware light is Meta's. Phoenix Fox never turns it off.
3. Add the GitHub Actions secrets in the table below. The next push to `main` uploads a build. Until every secret exists, the TestFlight workflow runs and skips. That skip is success, not a failure.
4. Install **TestFlight**, accept the Phoenix Fox invite, and install the build. Allow microphone, speech recognition, camera, photos, notifications, and contacts when the app asks. Bluetooth is for the glasses.
5. The app opens Meta AI to finish Wearables registration. Come back when Meta AI returns. The callback scheme is `phoenixfox`. If registration never finishes, the client token or the Meta release channel for app id `1651172483404286` is wrong. Developer Mode has to stay on.
6. Settings → Assistants: paste the relay URL (`https://…`) and the relay token. They stay on the phone. They are not GitHub secrets. Leave this screen so the app can register for push.
7. Put the glasses on. The phone should show them connected. Say **Jarvis**. You should hear the wake chime, then say **what time is it**. The reply is spoken from the phone, with no model call. If the reply comes from the phone earpiece, the glasses are not the audio route yet. Leave the Meta AI audio connection up and try again.
8. Say **Jarvis, ask Indy about the gate**. The app says it is on it, then speaks Indy's reply. That needs the worker from `relay/` deployed with the same token. Deploy steps are in [docs/RELAY_API.md](docs/RELAY_API.md).
9. Say **Jarvis, what do you see?** The glasses light comes on, one frame is taken, the light goes off, and you hear the answer. If the light never comes on, the camera permission inside Meta's registration was denied. Nothing is recorded unless you ask.
10. From another machine, `POST /push` an urgent line as Driver. The phone should speak it. Low priority lines wait for the morning brief. If push is silent, the inbox long-poll still delivers the line while the app is open. Check that `APNS_USE_SANDBOX` is `false` for this TestFlight build.

Say **Jarvis stop** to end the turn. The orange mic indicator is iOS. It stays while Jarvis is listening. That is required, not a hidden recording.

## Secrets

Open the GitHub repository, then **Settings → Secrets and variables → Actions → New repository secret**. One secret per row. Do not paste any of these into chat or into a committed file.

| Secret | What it is | Where to copy it |
| --- | --- | --- |
| `APPLE_TEAM_ID` | 10-character Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership details. It appears after Apple says the membership is active. |
| `ASC_KEY_ID` | App Store Connect API key id | [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → Integrations → App Store Connect API. |
| `ASC_ISSUER_ID` | Issuer ID above the keys list | Same page. |
| `ASC_KEY_P8` | The private key file | Generated once. Paste the whole `AuthKey_XXXX.p8`, including the BEGIN and END lines. Apple will not show it again. |
| `META_CLIENT_TOKEN` | Wearables client token | [Wearables Developer Center](https://wearables.developer.meta.com/) → Cinder and Crown LLC → Phoenix Fox. It looks like `AR\|1651172483404286\|…`. |

These are not secrets and are already in the app:

| Value | Where |
| --- | --- |
| Meta App ID `1651172483404286` | Info.plist `MWDAT` → `MetaAppID` |
| Bundle ID `com.cinderandcrown.phoenixfox` | The Xcode target |
| App name Phoenix Fox | Home screen and App Store |
| URL scheme `phoenixfox` | The Meta registration callback |

The simulator compile does not need any secret. Debug builds use the development push environment. The TestFlight archive uses production push. The worker's `APNS_USE_SANDBOX` is `false` for that archive. Set it to `true` only if you later install a development-signed build from Xcode.

## Relay and push

The worker is not deployed by this repo. From `relay/`, after `npm install`:

```bash
npx wrangler secret put RELAY_TOKEN
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APPLE_TEAM_ID
npx wrangler secret put APNS_KEY_P8
npx wrangler deploy
```

`APNS_KEY_P8` is the same kind of `.p8` as the App Store Connect key, but it is the **Apple Push Notifications** key (Apple Developer → Keys), not the App Store Connect API key. The topic is `com.cinderandcrown.phoenixfox`.

Put the worker URL and the same `RELAY_TOKEN` into Settings → Assistants.

## What v1 is supposed to do

| You say | What should happen |
| --- | --- |
| Jarvis | Wake chime. The session starts if the relay is saved. |
| what time is it / what's the date / battery | Spoken on the phone. No model. |
| ask Indy about … | Relay ask with `target_bot` Indy, then Indy's reply spoken. |
| what do you see | Camera light on, one frame, light off, spoken answer. |
| take a picture | Still saved to Photos. Light on for the shot. |
| remember this | Encrypted note on the phone. |
| A push from Driver | Spoken if urgent or normal. Low waits for the morning brief. |

If the relay is empty, Jarvis tells you to add it. Commands are not dropped in silence.

## If you later have a Mac

`project.yml` is the XcodeGen source. CI builds the committed `PhoenixFox.xcodeproj` and does not run XcodeGen. Copy `Config.xcconfig.example` to `Config.xcconfig` and `OpenVision/Config/Config.swift.example` to `OpenVision/Config/Config.swift` before a local build. Leave `META_CLIENT_TOKEN` out of git. The scheme is PhoenixFox. The source folder is still `OpenVision/` because that is the MIT project this build starts from.
