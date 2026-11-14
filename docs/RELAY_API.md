# Phoenix Fox relay

The worker in `relay/` is the mailbox between the phone and Fire Fox, Indy, Driver, and Rally. It is not deployed from this repo. The phone already calls these routes. Bots use the same routes from their own process.

The bearer is the token you paste into the app’s assistant settings and the token each bot sends. Set that exact value as the Wrangler secret `RELAY_TOKEN`. Every request must send `Authorization: Bearer <RELAY_TOKEN>`. A wrong or missing bearer is `401`. The comparison hashes both sides before checking them.

One deployment is one owner. The phone and the four bots share that bearer, so they share one mailbox. Each phone also registers its own APNs device token at `POST /device`. Pushes go to those devices. A second household is a second worker with a different secret.

Rate limits are per route, per minute, for that bearer: 30 asks, 120 pending polls, 60 replies, 180 reply polls, 30 pushes, 40 inbox polls, 10 device registrations. Over the limit the worker returns `429` and `Retry-After: 60`.

Long polls stop at 25 seconds even if `wait` is larger. The phone uses `wait=20` on replies and `wait=25` on the inbox.

## Phone

`POST /ask`

```json
{
  "id": "uuid",
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

`target_bot` is a roster name or `all`. The response is `{ "id", "status": "pending" }`.

`GET /reply/{id}?wait=20`

Until a bot finishes, `{ "status": "pending" }`. Then:

```json
{
  "id": "uuid",
  "status": "ready",
  "text": "Booked for seven.",
  "from_bot": "Fire Fox",
  "replies": [{ "text": "Booked for seven.", "from_bot": "Fire Fox" }],
  "done": true
}
```

For `target_bot: "all"` the `replies` array has one entry per bot.

`GET /inbox?wait=25`

```json
{ "messages": [{ "id": "...", "text": "Gate is open", "from_bot": "Driver", "priority": "urgent" }] }
```

Returned messages are removed. The phone speaks urgent lines immediately, speaks normal lines when it is quiet, and holds low lines for the morning brief.

`POST /device`

```json
{ "token": "<apns device token hex>", "platform": "ios" }
```

The hex token is the push address. It is not the bearer.

## Bots

Fire Fox, Indy, Driver, and Rally each poll their own name. An ask whose `target_bot` is `all` is visible to every bot.

`GET /pending?target_bot=Fire%20Fox&wait=20`

```json
{
  "asks": [{
    "id": "uuid",
    "text": "book a table",
    "transcript": "Jarvis, book a table",
    "intent": "message",
    "target_bot": "Fire Fox",
    "context": [],
    "reply_to": "optional"
  }]
}
```

`POST /reply/{id}`

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

`POST /push`

```json
{ "text": "Gate is open", "from_bot": "Driver", "priority": "urgent" }
```

`priority` is `urgent`, `normal`, or `low`. The message is stored for `GET /inbox`. Urgent and normal messages are also sent through APNs when a device token and the APNs secrets exist. Low messages stay in the inbox and do not wake the phone. If the APNs secrets are unset, the inbox write still succeeds and the response says `"apns": "skipped"`.

## APNs

Token auth, ES256. The `.p8` contents, the key id, and the Apple team id are secrets. The topic is `com.cinderandcrown.phoenixfox`. TestFlight and the App Store use production APNs, so `APNS_USE_SANDBOX` is `"false"` in `wrangler.toml`. Set it to `"true"` only for a build installed from Xcode with a development provisioning profile. Urgent pushes include `content-available` so the phone wakes and speaks the inbox line. The banner is separate. The inbox is still the source of truth.

Urgent pushes use an alert. Normal pushes are silent (`content-available`) so the phone pulls the inbox. The inbox is the source of truth. The push only wakes the app.

## Deploy

Do this from `relay/` after `npm install`. Do not commit secrets. `.dev.vars` is gitignored. Start from `.dev.vars.example` for local `wrangler dev`.

```bash
npx wrangler secret put RELAY_TOKEN
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APPLE_TEAM_ID
npx wrangler secret put APNS_KEY_P8
```

Paste the full `.p8` file, including the BEGIN and END lines, into `APNS_KEY_P8`. Then:

```bash
npx wrangler deploy
```

Put the worker URL and the same `RELAY_TOKEN` into the app’s assistant settings. This checkout does not run deploy.
