# Phoenix Fox relay

The worker in `relay/` is the mailbox between the phone and Fire Fox, Indy, Driver, and Rally. The phone posts an ask, a bot answers it, and the phone reads the answer. Bots can also push a message to the phone.

The owner's relay runs at `https://phoenix-fox-relay.cinderandcrown.workers.dev`.

## Rules for every request

Every request sends `Authorization: Bearer <RELAY_TOKEN>`. The token is the Wrangler secret `RELAY_TOKEN`, the value pasted into the app's assistant settings, and the value each bot holds. A missing or wrong bearer gets `401` before the request reaches the mailbox. The comparison hashes both sides first, so its timing says nothing about the token.

Send an ordinary `User-Agent`. Cloudflare answers `403` with error 1010 to clients it takes for bare scripts, and Python's default `Python-urllib/3.x` is one of them. Any descriptive value works, for example `IndyBot/1.0`.

Request bodies are JSON objects of at most 1.2 MB. A larger body gets `413`.

One deployment is one owner. The phone and the four bots share the bearer, so they share one mailbox. A second household is a second worker with a different secret.

Rate limits are per route and per minute: 30 asks, 120 pending polls, 60 replies, 180 reply polls, 30 pushes, 40 inbox polls, 10 device registrations, 30 health checks. Over the limit the worker returns `429` and `Retry-After: 60`.

Long polls stop at 25 seconds even if `wait` is larger. The phone uses `wait=20` on replies and `wait=25` on the inbox.

An ask is kept for 15 minutes. A pushed message is kept for 24 hours or until the phone reads it.

## Phone

### `POST /ask`

```json
{
  "id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
  "text": "book a table",
  "transcript": "Jarvis, book a table",
  "timestamp": "2026-11-14T12:00:00Z",
  "intent": "message",
  "target_bot": "Fire Fox",
  "context": [{ "role": "user", "text": "book a table" }],
  "reply_to": "optional inbox id",
  "image": "optional base64 jpeg",
  "images": ["optional extra base64 jpegs"]
}
```

`id` and `text` are required. `id` is 1 to 128 letters, digits, or `. _ : -`; the app sends a UUID. `target_bot` is a roster name or `all`, and defaults to `Fire Fox`. Bot names are matched without regard to case.

The response is `202` with:

```json
{ "id": "…", "status": "pending", "delivery": "webhook" }
```

`delivery` is `webhook` when the relay is posting the ask to the bot, and `poll` when the ask waits for the bot to fetch it. Posting the same `id` again returns the existing ask with `200` and sends nothing twice.

### `GET /reply/{id}?wait=20`

Until a bot finishes, `{ "id": "…", "status": "pending" }`. Then:

```json
{
  "id": "…",
  "status": "ready",
  "text": "Booked for seven.",
  "from_bot": "Fire Fox",
  "replies": [{ "text": "Booked for seven.", "from_bot": "Fire Fox" }],
  "done": true
}
```

For `target_bot: "all"` the `replies` array has one entry per bot and `text` joins them. An id the relay does not know gets `404`.

### `GET /inbox?wait=25`

```json
{ "messages": [{ "id": "…", "text": "Gate is open", "from_bot": "Driver", "priority": "urgent" }] }
```

Returned messages are removed. The phone speaks urgent lines immediately, speaks normal lines when it is quiet, and holds low lines for the morning brief.

### `POST /device`

```json
{ "token": "<apns device token hex>", "platform": "ios", "environment": "production" }
```

The hex token is the push address. It is not the bearer. `environment` is optional and is `production` or `sandbox`; see [APNs](#apns). The relay keeps the eight most recently registered devices.

## Bots

A bot learns about an ask in one of two ways. With a webhook, the relay posts the ask to the bot the moment the phone sends it, and the bot does nothing in between. Without one, the bot polls `/pending`. Webhooks are the cheaper way: a poll keeps a request open, and an idle bot pays for it.

### Webhooks

Set the secret `BOT_WEBHOOKS` to a JSON object from bot name to URL:

```json
{
  "Fire Fox": "https://firefox.example.com/relay",
  "Indy": "https://indy.example.com/relay",
  "Driver": { "url": "https://driver.example.com/relay", "secret": "a key only Driver holds" }
}
```

A URL must be `https` and must not contain a user name or password. Plain `http` is accepted only for `localhost`, for trying a bot under `wrangler dev`. A bot that is not listed keeps polling. `GET /health` shows which bots have a webhook and what, if anything, is wrong with the configuration.

When the phone posts an ask for a listed bot, the relay sends that bot:

```http
POST /relay HTTP/1.1
Content-Type: application/json
User-Agent: PhoenixFoxRelay/1 (+https://github.com/cinderandcrown/phoenix-fox)
X-Relay-Event: ask
X-Relay-Delivery: 0b9f6a0e-6c1f-4a53-8f43-9d2f0a4c1c11
X-Relay-Timestamp: 1794628562
X-Relay-Signature: v1=8ca5221428c4b93d4ae4544da031735322fa553401ca9fbe7cbeb0cae1b8b55b
```

```json
{
  "event": "ask",
  "delivery": "0b9f6a0e-6c1f-4a53-8f43-9d2f0a4c1c11",
  "bot": "Indy",
  "ask": {
    "id": "…",
    "text": "book a table",
    "transcript": "Jarvis, book a table",
    "timestamp": "2026-11-14T12:00:00Z",
    "intent": "message",
    "target_bot": "Indy",
    "context": []
  },
  "reply_url": "https://phoenix-fox-relay.cinderandcrown.workers.dev/reply/…"
}
```

`ask` has the same fields the phone sent, including `image`, `images`, `location`, and `reply_to` when present. An ask for `all` goes to every listed bot, each with its own `bot` value.

**Check the signature before trusting the body.** The signature is the hex HMAC-SHA256 of the timestamp, a full stop, and the raw request body, keyed with the signing secret. The signing secret is the bot's own `secret` from `BOT_WEBHOOKS` if it has one, otherwise the Wrangler secret `WEBHOOK_SECRET`, otherwise `RELAY_TOKEN`. Compute it over the bytes as received, before parsing. Reject a request whose timestamp is more than five minutes from the bot's clock, so a captured request cannot be replayed later.

```python
import hashlib, hmac, time

def verified(headers, raw_body: bytes, secret: str) -> bool:
    timestamp = headers.get("X-Relay-Timestamp", "")
    if not timestamp.isdigit() or abs(time.time() - int(timestamp)) > 300:
        return False
    expected = "v1=" + hmac.new(secret.encode(), timestamp.encode() + b"." + raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, headers.get("X-Relay-Signature", ""))
```

```javascript
import { createHmac, timingSafeEqual } from "node:crypto";

function verified(headers, rawBody, secret) {
  const timestamp = headers["x-relay-timestamp"] ?? "";
  if (!/^\d+$/.test(timestamp) || Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;
  const expected = Buffer.from("v1=" + createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex"));
  const given = Buffer.from(headers["x-relay-signature"] ?? "");
  return given.length === expected.length && timingSafeEqual(given, expected);
}
```

**Answer within ten seconds.** The bot has two ways to reply:

- Return `2xx` straight away and post the answer to `reply_url` when it is ready, exactly as a polling bot does with `POST /reply/{id}`. Use this for anything that takes thought.
- Return `200` with `Content-Type: application/json` and `{ "text": "Booked for seven." }`. The relay records that as the bot's reply and the bot makes no second call. The reply is credited to the bot the webhook belongs to.

**Failures fall back to the poll.** The relay tries a delivery three times over about five seconds when the bot is unreachable, times out, or answers `408`, `425`, `429`, or `5xx`. Any other status ends the delivery at once, and a redirect is not followed. Each attempt carries the same `X-Relay-Delivery` value and a fresh timestamp and signature, so a bot that receives one delivery twice can ignore the repeat. An ask whose delivery failed appears in `/pending`. A bot with a webhook should still poll now and then, for example once a minute and when it starts, to pick up anything a webhook missed.

### `GET /pending?target_bot=Fire%20Fox&wait=20`

```json
{
  "asks": [{
    "id": "…",
    "text": "book a table",
    "transcript": "Jarvis, book a table",
    "intent": "message",
    "target_bot": "Fire Fox",
    "context": [],
    "reply_to": "optional"
  }]
}
```

Each bot polls its own name. An ask whose `target_bot` is `all` is visible to every bot.

An ask a webhook already gave to the polling bot is left out, so a bot that uses both never handles one twice. An ask whose webhook is still being tried is left out for up to a minute. Add `include_delivered=1` to see everything; each ask then carries `deliveries`, with a `state` of `sending`, `delivered`, or `failed` per bot, the number of attempts, and the last HTTP status.

### `POST /reply/{id}`

One bot:

```json
{ "text": "Booked for seven.", "from_bot": "Fire Fox" }
```

That marks a single-bot ask ready. An all-hands ask stays pending until four different `from_bot` values have replied, or until a bot sends `"done": true`.

A bot that already collected the others can finish in one call:

```json
{
  "done": true,
  "replies": [
    { "text": "Clear.", "from_bot": "Fire Fox" },
    { "text": "On it.", "from_bot": "Indy" }
  ]
}
```

An ask that is unknown or older than 15 minutes gets `404`.

### `POST /push`

```json
{ "text": "Gate is open", "from_bot": "Driver", "priority": "urgent" }
```

`priority` is `urgent`, `normal`, or `low`. The message is stored for `GET /inbox`. The response is `202` with `{ "id", "status": "queued", "apns" }`, where `apns` is `sent`, `partial`, `failed`, or `skipped`. The inbox write succeeds whatever happens to the push.

## Status

### `GET /health`

```json
{ "ok": true, "apns": true, "devices": 1, "webhooks": ["Fire Fox", "Indy"], "webhook_problems": [] }
```

`apns` says whether the three APNs secrets are set. `webhooks` lists the bots that have a usable webhook. `webhook_problems` names each entry in `BOT_WEBHOOKS` that was rejected and why. The response never contains a URL or a secret. Like every route, it needs the bearer.

## APNs

Token auth, ES256. The `.p8` contents, the key id, and the Apple team id are secrets. The topic is `com.cinderandcrown.phoenixfox`.

Urgent pushes use an alert, and also carry `content-available` so the app wakes and speaks the line without a tap. Normal pushes are silent (`content-available`) so the phone pulls the inbox. Low messages stay in the inbox and do not wake the phone. The inbox is the source of truth; the push only wakes the app. If the APNs secrets are unset, pushes are skipped and the inbox still works.

Apple runs two push services, and a device token works on only one of them. **A build installed from TestFlight or the App Store uses production. Only a build run from Xcode uses sandbox.** The relay sends to the service the phone named in `POST /device`. If the phone did not name one, it tries production first, or sandbox first when `APNS_USE_SANDBOX` is `"true"`. When Apple rejects the token as bad, the relay tries the other service and remembers which one worked. A token that neither service accepts, or that Apple reports as unregistered, is forgotten; the app registers again the next time it starts.

The relay keeps one provider token for 45 minutes, because Apple penalises a provider that makes a new one for every push.

## Deploy

Run these from `relay/` after `npm install`. Do not commit secrets. `.dev.vars` is gitignored; start from `.dev.vars.example` for local `wrangler dev`.

```bash
npx wrangler secret put RELAY_TOKEN
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APPLE_TEAM_ID
npx wrangler secret put APNS_KEY_P8
npx wrangler secret put BOT_WEBHOOKS     # optional
npx wrangler secret put WEBHOOK_SECRET   # optional
npx wrangler deploy
```

Paste the full `.p8` file, including the BEGIN and END lines, into `APNS_KEY_P8`. Paste `BOT_WEBHOOKS` as one line of JSON.

`npm test` runs the unit tests and `npm run check` type-checks. Both run in CI on every pull request that touches `relay/`.
