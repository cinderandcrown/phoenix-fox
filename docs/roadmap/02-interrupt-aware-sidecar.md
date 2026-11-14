# Feature card — Interrupt-Aware Sidecar (rank 2)

**Rank:** 2 of 3  
**Aligned with:** presence checklist “Interrupt respect”; accessibility Guide/callout paths; backlog proactive-nudge rules  
**Status:** Proposed only — **do not build in this pass.**

## User job
Hear only the next useful cue when walking or working — never talk over the wearer, never stack callouts, never require looking at the phone.

## Trigger
On-device signals: worn state, hinge, walking (phone CoreMotion or gated DAT motion if owner-experimental), barcode/OCR edge, Guide mode active. Always Interrupt-aware.

## Input
DeviceState (don/hinge/battery/thermal), optional motion samples behind `headGestures` owner gate, last caption/OCR line.

## Capability requirement
- Publishable: DeviceState listeners, phone mic TTS  
- Optional experimental: `MWDATMotion` for nod/shake ack — **must** fall back to spoken yes/no  
- Displayless-first; Display card is a later enhancement only

## Output
≤8-word spoken cue; haptics optional on phone; never auto-start camera.

## Fallback
If speaking/listening/busy: queue at most one cue or drop. If glasses unpaired: phone banner + spoken line when app is foreground.

## Privacy cost
No continuous room recording; cues derived from on-device triggers; no people-ID.

## Success metric
Cue interruption rate (talk-over events) &lt;5% of sessions; wearer “quiet when I needed quiet” ≥4/5.

## Test strategy
- Unit: Interrupt state machine, queue depth 0/1, quiet-period gate  
- Acceptance scenario 7 mapping  
- Hardware: Adventurer walk with Guide on/off  
- Mock Device Kit: don/hinge edges without camera
