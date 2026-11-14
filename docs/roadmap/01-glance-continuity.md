# Feature card — Glance Continuity (rank 1)

**Rank:** 1 of 3 (highest presence leverage, Adventurer-safe with 1.0.1)  
**Aligned with:** presence north star (`docs/DESIGN_PRINCIPLES.md`); backlog W6 Promise ledger / A* ambient memory themes in `docs/INNOVATION_BACKLOG.md`  
**Status:** Proposed only — **do not build in the engineering-standard conformance pass.**

## User job
Keep a short shared memory of what wearer and Jarvis just saw or decided, so the next hands-free turn (“what was that?”, “remind me”, “same place”) continues the moment without re-waking into a blank Q&A.

## Trigger
On-device: end of a look / spoken decision / place change (significant location or worn+hinge edge), gated by Interrupt, quiet period, and owner tunable.

## Input
Last scene labels (on-device Vision), last spoken commitment text, optional single stream frame thumbnail kept only in RAM for the live window; no cloud export by default.

## Capability requirement
- DAT camera stream (publishable) when a look is already open  
- Phone Speech / Vision  
- **Does not** require Display, Neural Band, MWDATSpeech, or experimental photo

## Output
One short spoken line naming the shared referent (“Still on the blue label”) plus phone transcript row; optional “send to phone” on request.

## Fallback
If no recent referent: say so and offer a new look. If camera denied: phone-only memory of spoken commitments.

## Privacy cost
Bounded in-memory window (minutes); no bystander face gallery; no automatic cloud upload; clear forget command.

## Success metric
≥40% of follow-ups in the live window resolve without a new wake+look; wearer rates “felt continuous” ≥4/5 in beta diary.

## Test strategy
- Unit: window eviction, Interrupt gate, forget command  
- Mock Device Kit: stream start/stop + disconnect clears RAM buffer  
- Hardware smoke: Adventurer look → follow-up without re-wake  
- Never treat simulator as glasses proof
