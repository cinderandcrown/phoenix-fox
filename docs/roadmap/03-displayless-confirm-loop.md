# Feature card — Displayless Confirm Loop (rank 3)

**Rank:** 3 of 3 (high trust; unlocks W5 “assistants can ask you” and Workshop confirms)  
**Aligned with:** presence “collaborative”; backlog W5 / nod-shake patterns; Adventurer constraints  
**Status:** Proposed only — **do not build in this pass.**

## User job
Answer a yes/no from Jarvis or an assistant without touching the phone — while walking — with an unmistakable confirm/deny that never silently defaults to yes.

## Trigger
Assistant or Jarvis poses a yes/no that needs wearer consent (file day sheet, send photo to Indy, act on a standing order).

## Input
Spoken “yes”/“no” (phone or gated `MWDATSpeech`); optional two-nod / shake via `MWDATMotion` when `headGestures` owner gate is on.

## Capability requirement
- Required publishable path: phone speech  
- Optional experimental: motion gestures, on-glasses speech — each behind existing capability gates with spoken fallback  
- No Display / Neural Band required for v1

## Output
Clear prompt (“Nod twice or say yes to send Indy this photo”), then confirmation of the choice; timeout cancels with spoken “cancelled”.

## Fallback
Timeout → cancel (never yes). Experimental motion unavailable → speech only. Glasses absent → phone button row.

## Privacy cost
Consent audio may leave device only if wearer already opted into cloud STT; default on-device speech when available; photo send still needs explicit yes.

## Success metric
&lt;1% accidental confirms in beta; median time-to-answer &lt;4s hands-free; zero silent yes defaults in tests.

## Test strategy
- Unit: timeout=cancel, illegal double-yes ignored, gate off ⇒ speech-only  
- Mock Device Kit: motion simulate nod/shake when kit available in CI Mac  
- Hardware: Adventurer confirm/deny with capture light rules untouched  
- Map to CAPABILITIES scenarios 5 and 8
