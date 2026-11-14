# Phoenix Fox

Phoenix Fox is an iOS companion app for Meta AI glasses. You talk to it through the glasses, it can look through their camera when you ask, and it hands work to your own team of assistants: Fire Fox, Indy, Driver, and Rally.

Say **Jarvis** to wake it. Jarvis is only the spoken wake word inside the app. "Hey Meta" stays Meta's.

[![CI](https://github.com/cinderandcrown/phoenix-fox/actions/workflows/ci.yml/badge.svg)](https://github.com/cinderandcrown/phoenix-fox/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

## Status

This is pre-release software. The app compiles and its unit tests run in GitHub Actions. It has not yet been run on a pair of glasses, so nothing here is claimed to work on a device until the owner has tried it. [docs/FEATURE_PARITY.md](docs/FEATURE_PARITY.md) lists every feature with what is built, what is partial, and what Meta or iOS does not allow.

The first target is Meta Glasses Adventurer, which has a camera, microphones, and speakers and no lens display.

## How it works

```
 glasses mic ──Bluetooth──▶ iPhone: wake word, then on-device Whisper
                                      │
                    simple request ───┤──▶ answered on the phone (time, timers, notes)
                                      │
                    one look ─────────┤──▶ one photo from the glasses camera, capture light on
                                      │
                    work for a bot ───┴──▶ relay (Cloudflare Worker) ──▶ Fire Fox, Indy, Driver, Rally
                                                    │
 glasses speakers ◀── spoken reply ◀── iPhone ◀─────┘  replies, and alerts by inbox or push
```

- **On the phone first.** The wake word, speech to text, the time, timers, reminders, and notes use no cloud model. A look sends one compressed photo, and a watch session sends a frame only when the scene has changed. This keeps the cost of each user low.
- **The relay.** The app never talks to a bot directly. It sends an ask to a small Cloudflare Worker in [`relay/`](relay/), and the bots collect and answer it. The interface is in [docs/RELAY_API.md](docs/RELAY_API.md). The relay token is typed into the app and kept in the iPhone's Keychain.
- **One output, one input.** Every reply is spoken. On glasses that report a display, the same call also draws a card on the lens. A tap, a band gesture, or the capture button enters the same turn as a spoken command. Display glasses and the Neural Band therefore need no second code path.
- **Other providers.** Settings can switch the assistant to Grok, OpenAI, Gemini Live, Claude, a Hermes or OpenClaw server, Apple Intelligence, or a model that runs on the phone.

## Privacy and the capture light

- The camera runs only when you ask for a look, a picture, a recording, or a watch session, and the glasses' capture light is on whenever it runs. That light is Meta's hardware. Phoenix Fox cannot turn it off and does not try to.
- There is no hidden recording and no firmware change.
- The microphone is on while Jarvis is listening, and iOS shows its orange indicator the whole time.
- Notes you ask it to remember are encrypted on the phone. "Mind meld", the running log of what you said, is off until you turn it on, and it keeps words and not photos.
- API keys and the relay token are stored in the Keychain. No secret is in this repository.

## Using it

There is no public App Store build. The owner's builds are made by GitHub Actions and installed through TestFlight. [SETUP.md](SETUP.md) is the step-by-step guide: getting a build, registering the glasses, connecting the relay, and what to say.

## Repository layout

| Path | What it holds |
| --- | --- |
| `OpenVision/` | The iOS app. The folder keeps the name of the project it started from. |
| `OpenVisionTests/` | Unit tests. They run on a simulator in CI. |
| `relay/` | The Cloudflare Worker that carries asks, replies, and alerts between the phone and the bots, with its own tests. |
| `scripts/` | Project-file sync, App Store Connect calls, and the signed-app check, with their tests. |
| `Vendor/` | Kokoro text to speech and its dependencies, kept as their authors ship them. |
| `docs/` | Feature status, the relay interface, notes on the glasses SDK, and design notes inherited from OpenVision. |
| `.github/workflows/` | `ci.yml` builds and tests the app. `testflight.yml` signs and uploads it. |

## Building

The compiler is GitHub Actions on macOS with Xcode 26. No Apple account is needed for the simulator build.

- **CI** runs on every pull request: it checks that the project file lists every source file, builds for the simulator, fails on any warning in Phoenix Fox's own code, and runs the unit tests. A second job tests the scripts.
- **TestFlight** runs when started by hand or by a version tag. It archives, signs, checks the signed app, has Apple validate it, and uploads.

The app is built in Swift 5 language mode with complete strict-concurrency checking. On a Mac, see the last section of [SETUP.md](SETUP.md).

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) says how to make a change and what CI checks. Security problems are reported privately, as [SECURITY.md](SECURITY.md) describes. Write your own code. Do not copy code whose license does not allow Apache-2.0 use, and add a notice for any new dependency to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License and credits

Phoenix Fox is licensed under the [Apache License 2.0](LICENSE), copyright 2026 Cinder and Crown LLC. The name Phoenix Fox and its branding are trademarks of Cinder and Crown LLC and are not licensed with the code. See [NOTICE](NOTICE).

The app started from [OpenVision](https://github.com/rayl15/OpenVision) by its contributors, under the MIT license. That notice and those of every other dependency are kept in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

The Meta Wearables Device Access Toolkit is a binary dependency under Meta's own terms. Phoenix Fox is not made by or endorsed by Meta.
