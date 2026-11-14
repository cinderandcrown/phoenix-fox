# Security

Phoenix Fox handles a camera, a microphone, API keys, and a relay that speaks to the owner's assistants. Reports are welcome.

## Reporting a problem

Do not open a public issue for a security problem.

Use GitHub's private reporting: **Security → Report a vulnerability** on this repository, or [this link](https://github.com/cinderandcrown/phoenix-fox/security/advisories/new). Only the maintainers see the report.

Say what you found, how to reproduce it, and what it lets someone do. A suggested fix helps and is not required.

This is a small project. Expect an answer within a week. A fix for something serious comes before other work.

## What is in scope

- The iOS app in `OpenVision/`.
- The relay, a Cloudflare Worker, in `relay/`.
- The workflows in `.github/workflows/` and the scripts in `scripts/`.

Worth reporting:

- A way to reach the relay, or an assistant behind it, without the owner's token.
- A way to turn the glasses camera or microphone on without the wearer asking, or without the capture light.
- A key, token, photo, transcript, or health record leaving the phone when the app says it stays.
- A secret readable from the repository, its history, a workflow log, or a build artifact.
- A workflow that a pull request from a fork could use to read a secret or publish a build.
- A skill file or a relay message that makes the app do something its owner did not agree to.

Out of scope:

- Attacks that need the unlocked phone in hand.
- Problems in Meta's toolkit, Apple's frameworks, or another dependency. Report those to their owners, and tell us if Phoenix Fox makes one worse.
- The relay address being public. It is in the source on purpose, and every route needs the owner's token.

## Where secrets live

None are in this repository.

| Secret | Where it is kept |
| --- | --- |
| API keys, the relay token, sign-in tokens | The iPhone Keychain |
| Meta client token, Apple team and App Store Connect key | GitHub Actions secrets, and `Config.xcconfig` on a developer's machine, which Git ignores |
| The relay's token, webhook secrets, and push key | Cloudflare Worker secrets |

Identifiers that are public by design are in the source: the bundle ID, the Meta app ID, the universal link host, and the OAuth client IDs of the services the app can sign in to.

The TestFlight workflow is the only one that uses secrets. It runs for a tag, a manual run, or a pull request from a branch of this repository. It does not sign anything for a pull request from a fork.

If you find a secret that was committed by mistake, report it privately. It will be revoked and replaced. Removing it from the history comes second.

## Supported versions

Fixes go to `main` and to the next TestFlight build. Older builds are not patched.

## Safety

Some features help blind and low-vision people, and some read medicine labels. A failure there can hurt someone without being a security hole. Report those the same way if the details should not be public yet, or as an ordinary issue if they can be. Their limits are written down in `docs/`.
