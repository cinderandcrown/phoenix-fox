# Face recognition — retention schedule

> Publisher: **Cinder and Crown LLC**. Privacy contact: **privacy@cinderandcrown.com**.
> Face prints are biometric identifiers. This schedule is the written retention policy for Phoenix Fox.

## What is stored

| Item | Detail |
| --- | --- |
| Data | Numeric face print (Vision feature print), display name, spoken-consent timestamp, last match timestamp |
| Not stored | Photos, strangers / unenrolled faces, cloud copies |
| Where | On this iPhone only, AES-GCM sealed (`AccessStore`), file protection, excluded from iCloud backup |
| Never sent | Cloud AI, Meta, relay, or Cinder and Crown LLC servers |

## Consent

1. **Wearer opt-in** — Before the feature turns on, the wearer accepts a plain-language notice covering Texas CUBI and Illinois BIPA (in Settings or by spoken yes). Stored as `ov.faceRecognition.wearerNoticeAcceptedAt`.
2. **Per-person enrollment** — Enrollment is only after that person says **yes** to a spoken consent prompt. The yes is timestamped on the face record. No enrollment from passive sightings.
3. **Withdrawal** — “Forget [name]’s face”, “forget all faces”, Settings → Saved faces → Delete, or **Delete all my data**.

## Retention and deletion

| Trigger | Action |
| --- | --- |
| **Default retention** | Delete a person’s prints **30 days after the last successful match**. If never matched, 30 days after consent. |
| **Configurable** | Wearer may set retention from **1 to 30 days** in Accessibility settings. |
| **Immediate** | Forget this person / forget everyone / Delete all my data / uninstall. |
| **Strangers** | Unenrolled faces are **never** written to storage. |

## Purpose

Recognize people the wearer enrolled, after those people agreed, so Jarvis can say who is there. Not for advertising, not for strangers, not for law enforcement sharing.

## Contact

Questions or deletion requests: **privacy@cinderandcrown.com** (Cinder and Crown LLC).
