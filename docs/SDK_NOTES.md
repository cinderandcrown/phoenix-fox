# SDK notes — Phoenix Fox

Living citations for third-party SDKs and platform constraints. Dates are when the note was verified.

## Meta Wearables Device Access Toolkit (DAT)

- **Pin:** `meta-wearables-dat-ios` **1.0.1** (exact). See `project.yml`.
- **Audio:** HFP (mic + voice) and A2DP (stereo speaker) **cannot run at the same time** on the glasses. Phoenix Fox picks one link via `AudioRoutePolicy` / `MusicSessionPolicy`. HFP must settle (~0.7s) before the camera stream starts.
- **Experimental modules** (Speech, high-res stills, etc.): owner / beta channel only — see `BuildFlavor` and `GlassesCapabilitySettings`.
- **App Store / MFi:** Declaring `com.meta.ar.wearable` still requires Meta PPID authorization that Meta is not issuing to third parties as of Discussion [#313](https://github.com/meta/meta-wearables-dat-ios/discussions/313) (Sep 2026) and the iOS integration guide (checked 14 Nov 2026). TestFlight + release channel only until Meta opens publishing.

## Spotify iOS SDK + Web API

**Verified 14 November 2026** against:

- [Spotify iOS SDK](https://developer.spotify.com/documentation/ios) / [ios-sdk auth.md](https://github.com/spotify/ios-sdk/blob/master/docs/auth.md)
- [Quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes)
- [Developer access update (6 Feb 2026)](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security)

### Auth (no client secret in the app)

- Use **OAuth PKCE** (`authorization_code` + `code_verifier`). Do **not** embed a client secret.
- Spotify iOS SDK `SPTSessionManager` uses PKCE when `tokenSwapURL` / `tokenRefreshURL` are unset (ios-sdk `docs/auth.md`, verified 14 Nov 2026).
- Phoenix Fox implements PKCE in `SpotifyPKCEAuth` (ASWebAuthenticationSession → `phoenixfox://spotify-callback`) and stores tokens in the Keychain.
- Optional: a relay token-swap endpoint may be added later; not required for PKCE.

### App Remote

- `SPTAppRemote` controls the **Spotify iOS app** (play / pause / skip / play URI / player state).
- Spotify app **must be installed**. Non-Premium accounts hit App Remote / Web API playback limits — speak a Premium fallback (`MusicProviderError.needsPremium`).
- Link `SpotifyiOS.xcframework` from [spotify/ios-sdk](https://github.com/spotify/ios-sdk) for App Remote. Until linked, `#if canImport(SpotifyiOS)` is false and Phoenix Fox uses the **Web API player** endpoints (requires an active Connect device, usually the phone Spotify app).

### Developer Mode vs Extended Quota

| Mode | Users | Notes |
| --- | --- | --- |
| **Development Mode** (default) | **Up to 5** allowlisted Spotify users | Owner must be **Premium**. API quota buckets apply; non-allowlisted users get **403**. |
| **Extended Quota Mode** | Unlimited (after approval) | As of **15 May 2025**, Spotify accepts applications from **organizations only** (not individuals). Requirements include a registered business, launched service, **≥250k MAUs**, key markets, commercial viability, Developer Policy adherence. Review can take **up to six weeks**. |

**Public App Store release of Spotify features needs Extended Quota approval.** Until then, keep the Spotify Dashboard app in Development Mode and allowlist testers (max 5).

### Dashboard setup (human)

1. Create an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).
2. Add Redirect URI: `phoenixfox://spotify-callback`.
3. Put the **Client ID** in `Config.xcconfig` as `SPOTIFY_CLIENT_ID=…` (maps to Info.plist `SpotifyClientID`).
4. Allowlist tester Spotify emails under Users Management.
5. Before public launch: submit Quota Extension Request from a company email.

## Apple Music (MusicKit)

- Uses `MusicAuthorization`, `MusicCatalogSearchRequest`, `ApplicationMusicPlayer`.
- Entitlements: `com.apple.developer.music-kit`, `com.apple.developer.media-player`.
- Enable MusicKit on the App ID in the Apple Developer portal (human).
- System Now Playing: `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`.

## ShazamKit

- On-device match for “what song is this” (`ShazamIdentify`). Uses the mic; no Shazam account required for basic matching.
- Falls back to the active music provider’s now-playing if Shazam fails.

## Music ↔ glasses audio (design)

| Phase | Link | Behavior |
| --- | --- | --- |
| Music playing | **A2DP** | Stereo on glasses speakers |
| Wake word / command | **HFP** (brief) | Mic capture; music ducks / may pause (`duckOthers`) |
| Assistant TTS | Duck + short voice link | Soften music under speech |
| After command / speech | **A2DP** restore | Stereo must return — **checklist item** |

**Verified in unit tests:** `MusicSessionPolicy`, `MusicCommandParser`, `AudioRoutePolicy` exclusivity.  
**Needs on-glasses soak:** A2DP → HFP → A2DP after “Jarvis, skip” with Spotify/Apple Music playing; confirm stereo (not mono call quality) returns.
