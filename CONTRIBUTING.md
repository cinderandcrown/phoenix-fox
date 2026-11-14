# Contributing to Phoenix Fox

Phoenix Fox is an iOS companion app for Meta AI glasses, with a small relay in `relay/`. It is open source under the Apache License 2.0. [README.md](README.md) says what it does and how the repository is laid out.

## Before you start

- **Bugs and ideas** go in [issues](https://github.com/cinderandcrown/phoenix-fox/issues). Say what you did, what you expected, what happened, and which iPhone, iOS, and glasses you have.
- **Security problems** do not go in issues. See [SECURITY.md](SECURITY.md).
- For anything larger than a fix, open an issue first, so the work is wanted before you do it.

## Rules that do not bend

A change that breaks one of these will not be merged.

1. The camera runs only when the wearer asks, and the glasses' capture light is on whenever it runs. No hidden recording, and no change to the glasses' firmware.
2. No secret goes in the repository: no key, token, `.p8` file, or filled-in `Config.xcconfig`. Keys entered in the app are stored in the Keychain.
3. Write your own code. Do not copy code whose license does not allow use under Apache-2.0. A new dependency needs its notice added to [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
4. Keep the cost per user low. A feature that calls a model every few seconds needs a reason.

## Making a change

1. Fork the repository and make a branch from `main`.
2. Copy the two example config files. An empty Meta client token is enough to compile.

   ```bash
   cp Config.xcconfig.example Config.xcconfig
   cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift
   ```

3. If you add, move, or delete a Swift file, update the Xcode project with the script. Do not edit `project.pbxproj` by hand.

   ```bash
   python3 scripts/xcodeproj_sync.py          # update the project
   python3 scripts/xcodeproj_sync.py --check  # what CI runs
   ```

4. Put decisions in plain types that can be tested without a phone: parsing, routing, timing, limits. Add unit tests for them in `OpenVisionTests/`.
5. For the relay, run `npm ci`, `npm run check`, and `npm test` in `relay/`.
6. Open a pull request. Fill in the template, and say plainly what you ran and what you did not. "Not run on glasses" is a fine answer. A wrong "tested" is not.

## What CI checks

Every pull request is built by GitHub Actions on macOS with Xcode 26. No Apple account is needed.

- The project file lists every source file.
- The app builds for the simulator with complete strict-concurrency checking.
- There are no warnings in Phoenix Fox's own code. A warning fails the build.
- The unit tests pass on a simulator.
- The scripts' own tests pass, and the relay's when `relay/` changes.

The TestFlight workflow signs and uploads the owner's builds. It needs secrets, so it does nothing for a pull request from a fork.

## Style

- Swift 5 language mode with strict concurrency set to complete. UI and shared managers are `@MainActor`.
- Follow the file you are in: its naming, its comments, and its way of handling errors.
- Comments say why, not what.
- Words the wearer hears or reads are short and plain. Say what happened and what to do next.
- Documentation says what is built, what is only written, and what has not been run on glasses. [docs/FEATURE_PARITY.md](docs/FEATURE_PARITY.md) defines those words.

## License of contributions

By opening a pull request you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), as section 5 of that license describes.

The name Phoenix Fox and its branding are trademarks of Cinder and Crown LLC and are not licensed with the code. A fork that is distributed needs its own name and icon. See [NOTICE](NOTICE).
