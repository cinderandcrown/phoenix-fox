import { describe, expect, it } from "vitest";
import {
  DELIVERY_HEADER,
  EVENT_HEADER,
  SIGNATURE_HEADER,
  TIMESTAMP_HEADER,
  deliver,
  parseWebhooks,
  sign,
  targetsFor,
  type WebhookConfig,
} from "../src/webhooks";
import { harness, type Sent } from "./harness";

const SECRET = "signing-secret";
const HOOKS: WebhookConfig = {
  targets: [
    { bot: "Fire Fox", url: "https://bots.test/firefox", secret: SECRET },
    { bot: "Indy", url: "https://bots.test/indy", secret: "indy-secret" },
  ],
  problems: [],
};
const ASK = { id: "a1", text: "book a table", transcript: "Jarvis, book a table", intent: "message", target_bot: "Fire Fox" };

/** What a bot does to check a webhook: recompute the HMAC over "<timestamp>.<body>". */
async function verifies(sent: Sent, secret: string): Promise<boolean> {
  const timestamp = Number(sent.headers.get(TIMESTAMP_HEADER));
  return sent.headers.get(SIGNATURE_HEADER) === `v1=${await sign(secret, timestamp, sent.body)}`;
}

describe("webhook configuration", () => {
  it("is empty when nothing is configured", () => {
    expect(parseWebhooks(undefined, SECRET)).toEqual({ targets: [], problems: [] });
    expect(parseWebhooks("  ", SECRET)).toEqual({ targets: [], problems: [] });
  });

  it("reads a URL or a URL with its own secret", () => {
    const config = parseWebhooks(JSON.stringify({
      "Fire Fox": "https://bots.test/firefox",
      Indy: { url: "https://bots.test/indy", secret: "indy-secret" },
    }), SECRET);
    expect(config).toEqual(HOOKS);
  });

  it("reports what is wrong without repeating the URL", () => {
    const config = parseWebhooks(JSON.stringify({
      Driver: "http://bots.test/driver?key=hunter2",
      Rally: "https://user:hunter2@bots.test/rally",
      Indy: 7,
      all: "https://bots.test/all",
      "Fire Fox": "https://bots.test/firefox",
      "fire fox ": "https://bots.test/again",
    }), SECRET);
    expect(config.targets.map((target) => target.bot)).toEqual(["Fire Fox"]);
    expect(config.problems).toEqual([
      "Driver: url must be https",
      "Rally: url must not carry a user name or password",
      'Indy: expected a URL or { "url", "secret" }',
      '"all" is not a bot name',
      "fire fox: listed more than once",
    ]);
    expect(config.problems.join(" ")).not.toContain("hunter2");
  });

  it("accepts plain http only for this machine", () => {
    const config = parseWebhooks(JSON.stringify({
      Indy: "http://localhost:8788/hook",
      Driver: "http://127.0.0.1:8788/hook",
      Rally: "http://localhost.evil.test/hook",
      "Fire Fox": "ftp://localhost/hook",
    }), SECRET);
    expect(config.targets.map((target) => target.bot)).toEqual(["Indy", "Driver"]);
    expect(config.problems).toEqual(["Rally: url must be https", "Fire Fox: url must be https"]);
  });

  it("rejects text that is not a JSON object", () => {
    expect(parseWebhooks("{", SECRET).problems).toEqual(["BOT_WEBHOOKS is not valid JSON"]);
    expect(parseWebhooks("[]", SECRET).problems).toEqual(["BOT_WEBHOOKS must be a JSON object of bot name to URL"]);
  });

  it("refuses a webhook that nothing would sign", () => {
    expect(parseWebhooks('{"Indy":"https://bots.test/indy"}', "")).toEqual({ targets: [], problems: ["Indy: no signing secret"] });
  });

  it("matches a bot name without regard to case, and all to every bot", () => {
    expect(targetsFor(HOOKS, " fire fox").map((target) => target.bot)).toEqual(["Fire Fox"]);
    expect(targetsFor(HOOKS, "ALL").map((target) => target.bot)).toEqual(["Fire Fox", "Indy"]);
    expect(targetsFor(HOOKS, "Rally")).toEqual([]);
  });
});

describe("webhook signature", () => {
  it("matches a known HMAC-SHA256 value", async () => {
    // printf '1700000000.{"a":1}' | openssl dgst -sha256 -hmac signing-secret
    expect(await sign(SECRET, 1_700_000_000, '{"a":1}')).toBe("8ca5221428c4b93d4ae4544da031735322fa553401ca9fbe7cbeb0cae1b8b55b");
  });

  it("changes with the secret, the timestamp, and the body", async () => {
    const base = await sign(SECRET, 1_700_000_000, "{}");
    expect(base).toMatch(/^[0-9a-f]{64}$/);
    expect(await sign("other", 1_700_000_000, "{}")).not.toBe(base);
    expect(await sign(SECRET, 1_700_000_001, "{}")).not.toBe(base);
    expect(await sign(SECRET, 1_700_000_000, "{ }")).not.toBe(base);
  });
});

describe("webhook delivery", () => {
  it("posts a signed ask to the named bot and tells the phone a webhook has it", async () => {
    const relay = harness({ webhooks: HOOKS });
    const created = await relay.post("/ask", { ...ASK, image: "aGk=" });
    expect(created.status).toBe(202);
    expect(await created.json()).toEqual({ id: "a1", status: "pending", delivery: "webhook" });
    await relay.settle();

    expect(relay.sent).toHaveLength(1);
    const [sent] = relay.sent;
    expect(sent.url).toBe("https://bots.test/firefox");
    expect(sent.headers.get("content-type")).toBe("application/json");
    expect(sent.headers.get("user-agent")).toMatch(/^PhoenixFoxRelay\//);
    expect(sent.headers.get(EVENT_HEADER)).toBe("ask");
    expect(sent.headers.get(TIMESTAMP_HEADER)).toBe(String(Math.floor(relay.now() / 1000)));
    expect(await verifies(sent, SECRET)).toBe(true);
    expect(await verifies(sent, "wrong")).toBe(false);

    const body = JSON.parse(sent.body) as Record<string, unknown>;
    expect(body).toMatchObject({
      event: "ask",
      bot: "Fire Fox",
      delivery: sent.headers.get(DELIVERY_HEADER),
      reply_url: "https://relay.test/reply/a1",
      ask: { ...ASK, image: "aGk=", context: [] },
    });
    expect(Object.keys(body.ask as object)).not.toContain("deliveries");
    expect(Object.keys(body.ask as object)).not.toContain("replies");
  });

  it("signs each bot's webhook with that bot's secret", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", { ...ASK, target_bot: "indy" });
    await relay.settle();
    expect(relay.sent.map((sent) => sent.url)).toEqual(["https://bots.test/indy"]);
    expect(await verifies(relay.sent[0], "indy-secret")).toBe(true);
    expect(await verifies(relay.sent[0], SECRET)).toBe(false);
  });

  it("sends an all-hands ask to every bot that has a webhook", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", { ...ASK, target_bot: "all" });
    await relay.settle();
    expect(relay.sent.map((sent) => sent.url).sort()).toEqual(["https://bots.test/firefox", "https://bots.test/indy"]);
  });

  it("leaves an ask for a bot without a webhook to the poll", async () => {
    const relay = harness({ webhooks: HOOKS });
    const created = await relay.post("/ask", { ...ASK, target_bot: "Rally" });
    expect(await created.json()).toEqual({ id: "a1", status: "pending", delivery: "poll" });
    await relay.settle();
    expect(relay.sent).toEqual([]);
    const pending = await relay.read<{ asks: { id: string }[] }>("/pending?target_bot=Rally");
    expect(pending.asks.map((ask) => ask.id)).toEqual(["a1"]);
  });

  it("does not send the same ask twice when the phone repeats it", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", ASK);
    const again = await relay.post("/ask", ASK);
    expect(again.status).toBe(200);
    expect(await again.json()).toEqual({ id: "a1", status: "pending", delivery: "webhook" });
    await relay.settle();
    expect(relay.sent).toHaveLength(1);
  });

  it("hides a delivered ask from the bot's poll but still shows it on request", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", ASK);
    await relay.settle();
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toEqual([]);
    expect((await relay.read<{ asks: unknown[] }>("/pending")).asks).toEqual([]);
    const all = await relay.read<{ asks: { id: string; deliveries: Record<string, { state: string; attempts: number; status: number }> }[] }>(
      "/pending?target_bot=Fire%20Fox&include_delivered=1",
    );
    expect(all.asks).toHaveLength(1);
    expect(all.asks[0].deliveries["fire fox"]).toMatchObject({ state: "delivered", attempts: 1, status: 204 });
  });

  it("retries a failing webhook, then leaves the ask to the poll", async () => {
    const relay = harness({ webhooks: HOOKS }, () => new Response("down", { status: 503 }));
    await relay.post("/ask", ASK);
    await relay.settle();
    expect(relay.sent).toHaveLength(3);
    // The same delivery id on every attempt, so the bot can ignore a repeat.
    expect(new Set(relay.sent.map((sent) => sent.headers.get(DELIVERY_HEADER))).size).toBe(1);
    for (const sent of relay.sent) expect(await verifies(sent, SECRET)).toBe(true);
    const pending = await relay.read<{ asks: { id: string; deliveries: Record<string, { state: string; attempts: number; status: number }> }[] }>(
      "/pending?target_bot=Fire%20Fox",
    );
    expect(pending.asks.map((ask) => ask.id)).toEqual(["a1"]);
    expect(pending.asks[0].deliveries["fire fox"]).toMatchObject({ state: "failed", attempts: 3, status: 503 });
  });

  it("succeeds on a retry after a temporary failure", async () => {
    const relay = harness({ webhooks: HOOKS }, (_sent, index) => new Response(null, { status: index === 0 ? 502 : 200 }));
    await relay.post("/ask", ASK);
    await relay.settle();
    expect(relay.sent).toHaveLength(2);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toEqual([]);
  });

  it("does not retry a refusal", async () => {
    const relay = harness({ webhooks: HOOKS }, () => new Response(null, { status: 401 }));
    await relay.post("/ask", ASK);
    await relay.settle();
    expect(relay.sent).toHaveLength(1);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toHaveLength(1);
  });

  it("does not follow a redirect", async () => {
    const relay = harness({ webhooks: HOOKS }, () => new Response(null, { status: 302, headers: { location: "https://elsewhere.test/" } }));
    await relay.post("/ask", ASK);
    await relay.settle();
    expect(relay.sent.map((sent) => sent.url)).toEqual(["https://bots.test/firefox"]);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toHaveLength(1);
  });

  it("treats a network error as a failure and keeps the ask", async () => {
    const relay = harness({ webhooks: HOOKS }, () => {
      throw new TypeError("network");
    });
    const created = await relay.post("/ask", ASK);
    expect(created.status).toBe(202);
    await relay.settle();
    expect(relay.sent).toHaveLength(3);
    const pending = await relay.read<{ asks: { deliveries: Record<string, { status: number }> }[] }>("/pending?target_bot=Fire%20Fox");
    expect(pending.asks[0].deliveries["fire fox"].status).toBe(0);
  });

  it("keeps an ask out of the poll while its webhook is in flight, but not forever", async () => {
    let release: (response: Response) => void = () => {};
    const relay = harness({ webhooks: HOOKS }, () => new Promise<Response>((resolve) => { release = resolve; }));
    await relay.post("/ask", ASK);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toEqual([]);
    // The relay was restarted mid-delivery and the webhook never finished.
    relay.advance(61_000);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Fire%20Fox")).asks).toHaveLength(1);
    release(new Response(null, { status: 204 }));
    await relay.settle();
  });

  it("takes a reply from the webhook response", async () => {
    const relay = harness({ webhooks: HOOKS }, () => Response.json({ text: " Booked for seven. ", from_bot: "Someone Else" }));
    await relay.post("/ask", ASK);
    await relay.settle();
    const reply = await relay.read<Record<string, unknown>>("/reply/a1");
    // The reply is credited to the bot the webhook belongs to, whatever the response claims.
    expect(reply).toMatchObject({ status: "ready", text: "Booked for seven.", from_bot: "Fire Fox", done: true });
  });

  it("still accepts the reply at /reply after a webhook delivery", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", ASK);
    await relay.settle();
    expect(await relay.read("/reply/a1")).toEqual({ id: "a1", status: "pending" });
    await relay.post("/reply/a1", { text: "Booked for seven.", from_bot: "Fire Fox" });
    expect(await relay.read("/reply/a1")).toMatchObject({ status: "ready", text: "Booked for seven." });
  });

  it("keeps a reply that arrives while the webhook is still in flight", async () => {
    let release: (response: Response) => void = () => {};
    const relay = harness({ webhooks: HOOKS }, () => new Promise<Response>((resolve) => { release = resolve; }));
    await relay.post("/ask", ASK);
    await relay.post("/reply/a1", { text: "Already done.", from_bot: "Fire Fox" });
    release(Response.json({ text: "Late duplicate." }));
    await relay.settle();
    const reply = await relay.read<{ replies: unknown[]; text: string }>("/reply/a1");
    expect(reply.text).toBe("Already done.");
    expect(reply.replies).toHaveLength(1);
  });

  it("collects webhook replies for an all-hands ask without finishing early", async () => {
    const relay = harness({ webhooks: HOOKS }, (sent) => Response.json({ text: `from ${new URL(sent.url).pathname}` }));
    await relay.post("/ask", { ...ASK, target_bot: "all" });
    await relay.settle();
    expect(await relay.read("/reply/a1")).toEqual({ id: "a1", status: "pending" });
    await relay.post("/reply/a1", { text: "Clear.", from_bot: "Driver" });
    const done = await relay.post("/reply/a1", { text: "Clear.", from_bot: "Rally" });
    const body = await done.json() as { status: string; replies: { from_bot: string }[] };
    expect(body.status).toBe("ready");
    expect(body.replies.map((reply) => reply.from_bot).sort()).toEqual(["Driver", "Fire Fox", "Indy", "Rally"]);
  });

  it("shows an all-hands ask to a polling bot that has no webhook", async () => {
    const relay = harness({ webhooks: HOOKS });
    await relay.post("/ask", { ...ASK, target_bot: "all" });
    await relay.settle();
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Indy")).asks).toEqual([]);
    expect((await relay.read<{ asks: unknown[] }>("/pending?target_bot=Rally")).asks).toHaveLength(1);
    expect((await relay.read<{ asks: unknown[] }>("/pending")).asks).toHaveLength(1);
  });
});

describe("deliver", () => {
  it("re-signs each attempt with the current time", async () => {
    let now = 1_700_000_000_000;
    const stamps: string[] = [];
    const result = await deliver(HOOKS.targets[0], "ask", { ask: ASK }, {
      now: () => now,
      sleep: async (ms) => { now += ms; },
      send: async (request) => {
        stamps.push(request.headers.get(TIMESTAMP_HEADER) ?? "");
        return new Response(null, { status: 500 });
      },
    });
    expect(result).toEqual({ bot: "Fire Fox", delivered: false, attempts: 3, status: 500 });
    expect(stamps).toEqual(["1700000000", "1700000001", "1700000005"]);
  });
});
