# Device capabilities and release gates (review on every SDK upgrade)

The table below is a **planning matrix**, not proof a particular firmware/device supports a specific API. Always perform runtime capability checks and verify documented availability.

| Capability | Ray-Ban Meta (displayless) | Meta Ray-Ban Display | Engineering caution |
|---|---|---|---|
| Glasses camera | Check current SDK/device permission | Check current SDK/device permission | Capture lifecycle, permissions, frame budgets |
| Glasses microphone / audio | Check module production status | Check module production status | SDK `audio-streaming` skill notes experimental/production limitations |
| Speech / voice invocation | SDK/channel dependent | SDK/channel dependent | Check supported wake invocation and acknowledgment |
| Glasses visual display | **No** | **Yes** | Use documented DAT display/inputs |
| Gesture / Neural Band | Never assume | May be available on supported setup | Capability and optional hardware dependent |
| Motion / orientation | Device-specific | Device-specific | No assumption of ARKit/world mapping |
| Development without hardware | Some functions via Mock Device Kit | Real display tests require more than basic Mock Device Kit | Check current Display sample and simulator |
| iPhone UI + backend | Yes | Yes | Phone is primary companion and compute layer |

## Distribution risks

- Official Meta FAQ says DAT 1.0 launched September 30, 2026 and discovery/submission channels are evolving. https://developers.meta.com/wearables/faq/
- On September 28, 2026, a Meta staff reply stated Apple MFi/PPID review requirements for apps declaring `com.meta.ar.wearable` were still unresolved, while TestFlight and Meta release channels were available for testing. **Re-check current status before public App Store planning.** https://github.com/meta/meta-wearables-dat-ios/discussions/313
- Some official iOS SDK skills flag specific audio/capture features as **experimental and unavailable for production publishing**. Feature must be redesigned or postponed before shipping if that is still true.
- Publishing a phone-only app with no restricted integration may follow a different path; do not claim that a workaround is equivalent to approved Meta glasses integration.

## Minimum acceptance scenarios

Automated mapping (unit / skip reasons): `OpenVisionTests/CapabilitiesAcceptanceTests.swift` and the matrix in `docs/SDK_NOTES.md`. Simulator results are never glasses hardware results.

1. Clean install, no glasses paired → useful onboarding and preview.
2. Connect / register compatible glasses → visible status and permission intent.
3. Deny permission → no streaming; clear retry/settings path.
4. Start camera session → bounded preview, meaningful status, user-controlled stop.
5. Trigger AI action → correct reply grounded in current frame, timeouts, cancellation and no surprise cloud export.
6. Disconnect mid-inference → end session, discard stale output, repair UI state.
7. Background or interruption → documented teardown and safe restart.
8. Displayless glasses → spoken or phone fallback; no invisible display controls.
9. Display glasses → supported high-contrast UI, focus and inputs; real-device proof.
10. Release gate → documented SDK version, Apple/MFi/Meta distribution eligibility and user privacy disclosure.
