# Privacy / legal App Store blockers (code)

Implemented from `docs/legal/REVIEW_CHECKLIST.md` / `DATA_INVENTORY.md` (PR #18).

| Item | Status |
| --- | --- |
| FluidAudio exactVersion 0.15.5 + Package.resolved | Done |
| Qwen2.5-3B store exclusion | Done (`GemmaLocalModel.isOffered`) |
| AI consent per provider + Settings revoke | Done |
| Guide cloud descriptions default OFF | Done |
| PrivacyInfo systemUptime + collected types (set A) | Done |
| Log redaction of speech/prompts | Done |
| Conversation file protection + exclude backup | Done |
| Delete all my data | Done |
| NSAllowsArbitraryLoads removed | Done |
| About / Privacy / Terms / Licenses | Done |
| Relay default owner-only | Done |
| Feature flags (Nicholas decisions below) | Done |
| Face print auto-expiry 30 days (configurable 1–30) + CUBI/BIPA opt-in | Done |
| Publisher `Cinder and Crown LLC` + `privacy@cinderandcrown.com` | Done |
| Written retention schedule `docs/legal/FACE_RETENTION.md` | Done |

### Nicholas decisions (item 11)

| Flag | Decision |
| --- | --- |
| Meta DAT telemetry | **OFF** all builds (`MWDAT > Analytics > OptOut`, flag locked) |
| ChatGPT / SuperGrok OAuth | **Removed** from store/release; owner+flag only; API keys stay |
| Face recognition | **Keep**, default OFF until wearer CUBI/BIPA opt-in + attorney sign-off; spoken per-person consent; 30-day no-match expiry |
| Gemma 2 2B | Still pending (flag default OFF) |

**Still Nicholas:** publish privacy/terms pages; attorney sign-off before defaulting face recognition on; Gemma 2 2B license; Meta MFi / App Store Connect answers.
