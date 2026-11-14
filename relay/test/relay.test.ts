import { describe, expect, it } from "vitest";
import { handleRelay, type RelayDeps } from "../src/handle";
import { MemoryMailbox } from "../src/mailbox";

const TOKEN = "owner-token";

function harness(extra?: Partial<RelayDeps>) {
  let now = 1_700_000_000_000;
  const mailbox = new MemoryMailbox();
  const pushes: string[] = [];
  const deps: RelayDeps = {
    ownerToken: TOKEN,
    mailbox,
    now: () => now,
    sleep: async (ms) => {
      now += ms;
    },
    notify: async (_notice, deviceToken) => {
      pushes.push(deviceToken);
      return "sent";
    },
    ...extra,
  };
  const call = (path: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    if (!headers.has("authorization")) headers.set("authorization", `Bearer ${TOKEN}`);
    return handleRelay(new Request(`https://relay.test${path}`, { ...init, headers }), deps);
  };
  return { call, mailbox, pushes, advance: (ms: number) => { now += ms; } };
}

describe("relay mailbox", () => {
  it("rejects a missing or wrong bearer", async () => {
    const { call } = harness();
    const missing = await handleRelay(new Request("https://relay.test/pending"), {
      ownerToken: TOKEN,
      mailbox: new MemoryMailbox(),
      now: () => 0,
      sleep: async () => {},
      notify: async () => "skipped",
    });
    expect(missing.status).toBe(401);
    const wrong = await call("/pending", { headers: { authorization: "Bearer other" } });
    expect(wrong.status).toBe(401);
  });

  it("keeps an ask until the named bot replies", async () => {
    const { call } = harness();
    const created = await call("/ask", {
      method: "POST",
      body: JSON.stringify({
        id: "a1",
        text: "book a table",
        transcript: "Jarvis book a table",
        timestamp: "2026-11-14T00:00:00Z",
        intent: "takeover",
        target_bot: "Fire Fox",
        context: [{ role: "user", text: "book a table" }],
      }),
    });
    expect(created.status).toBe(202);
    const pending = await call("/pending?target_bot=Fire%20Fox");
    const listed = await pending.json() as { asks: { id: string; target_bot: string }[] };
    expect(listed.asks.map((ask) => ask.id)).toEqual(["a1"]);
    const other = await call("/pending?target_bot=Indy");
    expect(((await other.json()) as { asks: unknown[] }).asks).toEqual([]);
    const early = await call("/reply/a1");
    expect(((await early.json()) as { status: string }).status).toBe("pending");
    const posted = await call("/reply/a1", {
      method: "POST",
      body: JSON.stringify({ text: "Booked for seven.", from_bot: "Fire Fox" }),
    });
    expect((await posted.json() as { status: string }).status).toBe("ready");
    const ready = await call("/reply/a1");
    const body = await ready.json() as { status: string; text: string; from_bot: string };
    expect(body).toMatchObject({ status: "ready", text: "Booked for seven.", from_bot: "Fire Fox" });
  });

  it("holds an all-hands ask until each bot has replied", async () => {
    const { call } = harness();
    await call("/ask", {
      method: "POST",
      body: JSON.stringify({ id: "all", text: "status", transcript: "status", intent: "briefing", target_bot: "all" }),
    });
    for (const name of ["Fire Fox", "Indy", "Driver"]) {
      const response = await call("/reply/all", { method: "POST", body: JSON.stringify({ text: name, from_bot: name }) });
      expect((await response.json() as { status: string }).status).toBe("pending");
    }
    const last = await call("/reply/all", { method: "POST", body: JSON.stringify({ text: "Rally", from_bot: "Rally" }) });
    const body = await last.json() as { status: string; replies: { from_bot: string }[] };
    expect(body.status).toBe("ready");
    expect(body.replies).toHaveLength(4);
  });

  it("queues a push, wakes each registered device, and acks the inbox", async () => {
    const { call, pushes } = harness();
    const registered = await call("/device", { method: "POST", body: JSON.stringify({ token: "ab".repeat(32), platform: "ios" }) });
    expect((await registered.json() as { devices: number }).devices).toBe(1);
    const pushed = await call("/push", { method: "POST", body: JSON.stringify({ text: "Gate is open", from_bot: "Driver", priority: "urgent" }) });
    expect(pushed.status).toBe(202);
    expect((await pushed.json() as { apns: string }).apns).toBe("sent");
    expect(pushes).toEqual(["ab".repeat(32)]);
    const inbox = await call("/inbox?wait=25");
    const messages = (await inbox.json() as { messages: { text: string; from_bot: string; priority: string }[] }).messages;
    expect(messages).toEqual([{ id: expect.any(String), text: "Gate is open", from_bot: "Driver", priority: "urgent" }]);
    const again = await call("/inbox");
    expect((await again.json() as { messages: unknown[] }).messages).toEqual([]);
  });

  it("long-polls the inbox until a push arrives", async () => {
    let now = 0;
    const mailbox = new MemoryMailbox();
    let announced = false;
    const deps: RelayDeps = {
      ownerToken: TOKEN,
      mailbox,
      now: () => now,
      sleep: async (ms) => {
        now += ms;
        if (!announced) {
          announced = true;
          await mailbox.put("inbox:late", { id: "late", text: "now", from_bot: "Indy", priority: "normal", createdAt: now });
        }
      },
      notify: async () => "skipped",
    };
    const response = await handleRelay(new Request("https://relay.test/inbox?wait=20", {
      headers: { authorization: `Bearer ${TOKEN}` },
    }), deps);
    const body = await response.json() as { messages: { id: string }[] };
    expect(body.messages.map((item) => item.id)).toEqual(["late"]);
  });

  it("rate limits asks", async () => {
    const { call } = harness();
    let limited = 0;
    for (let i = 0; i < 31; i++) {
      const response = await call("/ask", { method: "POST", body: JSON.stringify({ id: `n${i}`, text: "hi", target_bot: "Rally" }) });
      if (response.status === 429) limited += 1;
    }
    expect(limited).toBe(1);
  });

  it("skips APNs for a low-priority push", async () => {
    const { call, pushes } = harness();
    await call("/device", { method: "POST", body: JSON.stringify({ token: "cd".repeat(32), platform: "ios" }) });
    const response = await call("/push", { method: "POST", body: JSON.stringify({ text: "later", from_bot: "Rally", priority: "low" }) });
    expect((await response.json() as { apns: string }).apns).toBe("skipped");
    expect(pushes).toEqual([]);
  });
});
