import { describe, expect, it } from "vitest";
import { handleRelay } from "../src/handle";
import { harness, TOKEN } from "./harness";

describe("relay mailbox", () => {
  it("rejects a missing or wrong bearer", async () => {
    const { call, deps } = harness();
    const missing = await handleRelay(new Request("https://relay.test/pending"), deps);
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
    expect(pushes.map((device) => device.token)).toEqual(["ab".repeat(32)]);
    const inbox = await call("/inbox?wait=25");
    const messages = (await inbox.json() as { messages: { text: string; from_bot: string; priority: string }[] }).messages;
    expect(messages).toEqual([{ id: expect.any(String), text: "Gate is open", from_bot: "Driver", priority: "urgent" }]);
    const again = await call("/inbox");
    expect((await again.json() as { messages: unknown[] }).messages).toEqual([]);
  });

  it("long-polls the inbox until a push arrives", async () => {
    let announced = false;
    const relay = harness();
    relay.deps.sleep = async (ms) => {
      relay.advance(ms);
      if (!announced) {
        announced = true;
        await relay.mailbox.put("inbox:late", { id: "late", text: "now", from_bot: "Indy", priority: "normal", createdAt: relay.now() });
      }
    };
    const body = await relay.read<{ messages: { id: string }[] }>("/inbox?wait=20");
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

describe("relay hardening", () => {
  it("turns away a caller without the bearer before reading anything", async () => {
    const { refusal } = await import("../src/edge");
    const request = (headers: Record<string, string>) => new Request("https://relay.test/ask", { method: "POST", headers, body: "{}" });
    expect((await refusal(request({}), TOKEN, 100))?.status).toBe(401);
    expect((await refusal(request({ authorization: "Bearer nope" }), TOKEN, 100))?.status).toBe(401);
    expect((await refusal(request({ authorization: `Bearer ${TOKEN}` }), "", 100))?.status).toBe(500);
    expect((await refusal(request({ authorization: `Bearer ${TOKEN}`, "content-length": "101" }), TOKEN, 100))?.status).toBe(413);
    expect(await refusal(request({ authorization: `Bearer ${TOKEN}` }), TOKEN, 100)).toBeNull();
  });

  it("rejects a body that is too large even when its length was not declared", async () => {
    const { call } = harness();
    const chunk = new TextEncoder().encode("x".repeat(100_000));
    let sent = 0;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (sent++ < 20) controller.enqueue(chunk);
        else controller.close();
      },
    });
    const response = await call("/ask", { method: "POST", body, duplex: "half" } as RequestInit);
    expect(response.status).toBe(413);
  });

  it("rejects an ask id that is not a plain token", async () => {
    const { post } = harness();
    expect((await post("/ask", { id: "a/../b", text: "hi" })).status).toBe(400);
    expect((await post("/ask", { id: "x".repeat(129), text: "hi" })).status).toBe(400);
    expect((await post("/ask", { id: "3F2504E0-4F89-11D3-9A0C-0305E82C3301", text: "hi" })).status).toBe(202);
  });

  it("starts a new rate window each minute", async () => {
    const { post, advance } = harness();
    for (let i = 0; i < 30; i++) expect((await post("/ask", { id: `a${i}`, text: "hi" })).status).toBe(202);
    const over = await post("/ask", { id: "over", text: "hi" });
    expect(over.status).toBe(429);
    expect(over.headers.get("retry-after")).toBe("60");
    advance(60_000);
    expect((await post("/ask", { id: "next", text: "hi" })).status).toBe(202);
  });

  it("forgets asks and inbox messages that have expired, without a poll", async () => {
    const { post, mailbox, advance } = harness();
    await post("/ask", { id: "old", text: "hi" });
    await post("/push", { text: "old news", from_bot: "Indy", priority: "low" });
    advance(16 * 60 * 1000);
    await post("/ask", { id: "new", text: "hi" });
    expect(await mailbox.list("ask:")).toEqual(["ask:new"]);
    expect(await mailbox.list("inbox:")).toHaveLength(1);
    advance(24 * 60 * 60 * 1000);
    await post("/push", { text: "fresh", from_bot: "Indy", priority: "low" });
    expect(await mailbox.list("inbox:")).toHaveLength(1);
    expect(await mailbox.list("ask:")).toEqual([]);
  });

  it("does not answer for an ask that has expired", async () => {
    const { post, advance } = harness();
    await post("/ask", { id: "old", text: "hi" });
    advance(16 * 60 * 1000);
    expect((await post("/reply/old", { text: "late", from_bot: "Indy" })).status).toBe(404);
  });

  it("returns 404 for an ask nobody made", async () => {
    const { call } = harness();
    expect((await call("/reply/nope?wait=1")).status).toBe(404);
  });

  it("keeps both replies when two bots answer an all-hands ask at once", async () => {
    const { post, read } = harness();
    await post("/ask", { id: "all", text: "status", target_bot: "all" });
    await Promise.all([
      post("/reply/all", { text: "one", from_bot: "Indy" }),
      post("/reply/all", { text: "two", from_bot: "Driver" }),
    ]);
    const pending = await read<{ asks: { replies: unknown[] }[] }>("/pending?target_bot=all");
    expect(pending.asks[0].replies).toHaveLength(2);
  });
});

describe("devices", () => {
  const token = (pair: string) => pair.repeat(32);

  it("stores the push environment the phone reports", async () => {
    const { post, pushes } = harness();
    expect((await post("/device", { token: token("ab"), environment: "staging" })).status).toBe(400);
    expect((await post("/device", { token: "not hex" })).status).toBe(400);
    await post("/device", { token: token("AB"), environment: "production" });
    await post("/push", { text: "hi", from_bot: "Indy", priority: "urgent" });
    expect(pushes).toMatchObject([{ token: token("ab"), environment: "production" }]);
  });

  it("remembers the environment Apple accepted", async () => {
    const seen: (string | undefined)[] = [];
    const { post } = harness({
      notify: async (_notice, device) => {
        seen.push(device.environment);
        return { status: "sent", environment: "production" };
      },
    });
    await post("/device", { token: token("ab") });
    await post("/push", { text: "one", from_bot: "Indy", priority: "urgent" });
    await post("/push", { text: "two", from_bot: "Indy", priority: "urgent" });
    expect(seen).toEqual([undefined, "production"]);
  });

  it("forgets a device Apple says is gone and still queues the message", async () => {
    const relay = harness({ notify: async () => ({ status: "failed", gone: true }) });
    await relay.post("/device", { token: token("ab") });
    const pushed = await relay.post("/push", { text: "hi", from_bot: "Indy", priority: "urgent" });
    expect(await pushed.json()).toMatchObject({ status: "queued", apns: "failed" });
    expect(await relay.mailbox.list("device:")).toEqual([]);
    expect((await relay.read<{ messages: unknown[] }>("/inbox")).messages).toHaveLength(1);
  });

  it("queues the message when the push itself throws", async () => {
    const relay = harness({
      notify: async () => {
        throw new Error("apns down");
      },
    });
    await relay.post("/device", { token: token("ab") });
    const pushed = await relay.post("/push", { text: "hi", from_bot: "Indy", priority: "normal" });
    expect(await pushed.json()).toMatchObject({ status: "queued", apns: "failed" });
    expect(await relay.mailbox.list("device:")).toHaveLength(1);
  });

  it("keeps only the eight most recent devices", async () => {
    const relay = harness();
    for (let i = 0; i < 10; i++) {
      relay.advance(1000);
      // Ten registrations a minute are allowed; stay under it.
      if (i === 9) relay.advance(60_000);
      const response = await relay.post("/device", { token: token(`a${i}`) });
      expect(response.status).toBe(200);
    }
    const kept = await relay.mailbox.list("device:");
    expect(kept).toHaveLength(8);
    expect(kept).not.toContain(`device:${token("a0")}`);
    expect(kept).toContain(`device:${token("a9")}`);
  });
});

describe("health", () => {
  it("reports configuration without revealing it", async () => {
    const relay = harness({
      apnsReady: true,
      webhooks: {
        targets: [{ bot: "Indy", url: "https://bots.test/indy?key=hunter2", secret: "s3cret" }],
        problems: ["Driver: url must be https"],
      },
    });
    await relay.post("/device", { token: "ab".repeat(32) });
    const response = await relay.call("/health");
    const text = await response.text();
    expect(JSON.parse(text)).toEqual({ ok: true, apns: true, devices: 1, webhooks: ["Indy"], webhook_problems: ["Driver: url must be https"] });
    expect(text).not.toContain("hunter2");
    expect(text).not.toContain("s3cret");
    expect(text).not.toContain("bots.test");
  });

  it("needs the bearer like every other route", async () => {
    const { call } = harness();
    expect((await call("/health", { headers: { authorization: "Bearer nope" } })).status).toBe(401);
  });
});
