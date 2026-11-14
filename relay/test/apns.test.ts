import { describe, expect, it } from "vitest";
import { apnsConfigured, apnsJwt, defaultEnvironment, deliverApns, type ApnsDeps, type PushNotice } from "../src/apns";
import { MemoryMailbox } from "../src/mailbox";

const DEVICE = "aa".repeat(32);
const URGENT: PushNotice = { id: "1", text: "Gate is open", from_bot: "Driver", priority: "urgent" };

function decodePart(part: string): string {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

async function testKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer;
  let binary = "";
  for (const byte of new Uint8Array(pkcs8)) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey: pair.publicKey };
}

/** Apple, as far as the relay can tell: each host answers from a script and every request is kept. */
async function apple(answers: Record<string, (attempt: number) => Response>, env: Partial<ApnsDeps["env"]> = {}) {
  const { pem } = await testKey();
  let now = 1_700_000_000_000;
  const requests: { host: string; path: string; headers: Headers; body: string }[] = [];
  const deps: ApnsDeps = {
    env: { APNS_KEY_P8: pem, APNS_KEY_ID: "KEYID12345", APPLE_TEAM_ID: "TEAMID1234", ...env },
    now: () => now,
    cache: new MemoryMailbox(),
    send: async (request) => {
      const url = new URL(request.url);
      const seen = requests.filter((item) => item.host === url.host).length;
      requests.push({ host: url.host, path: url.pathname, headers: request.headers, body: await request.text() });
      return answers[url.host]?.(seen) ?? new Response(null, { status: 200 });
    },
  };
  return { deps, requests, advance: (ms: number) => { now += ms; } };
}

function rejection(status: number, reason: string): Response {
  return Response.json({ reason }, { status });
}

describe("APNs token auth", () => {
  it("signs a JWT that verifies with the same key", async () => {
    const { pem, publicKey } = await testKey();
    const jwt = await apnsJwt(pem, "KEYID12345", "TEAMID1234", 1_700_000_000);
    const [header, claims, signature] = jwt.split(".");
    const decodedClaims = JSON.parse(decodePart(claims)) as { iss: string };
    const raw = Uint8Array.from(decodePart(signature), (char) => char.charCodeAt(0));
    const ok = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      raw,
      new TextEncoder().encode(`${header}.${claims}`),
    );
    expect(ok).toBe(true);
    expect(decodedClaims.iss).toBe("TEAMID1234");
  });

  it("reuses one provider token until it is 45 minutes old", async () => {
    const { deps, requests, advance } = await apple({});
    await deliverApns(deps, URGENT, { token: DEVICE });
    advance(44 * 60 * 1000);
    await deliverApns(deps, URGENT, { token: DEVICE });
    advance(2 * 60 * 1000);
    await deliverApns(deps, URGENT, { token: DEVICE });
    const tokens = requests.map((request) => request.headers.get("authorization"));
    expect(tokens[0]).toBe(tokens[1]);
    expect(tokens[2]).not.toBe(tokens[0]);
  });

  it("replaces a provider token Apple rejects, once", async () => {
    const { deps, requests } = await apple({
      "api.push.apple.com": (attempt) => attempt === 0 ? rejection(403, "ExpiredProviderToken") : new Response(null, { status: 200 }),
    });
    // A cached token from an earlier push, so the first attempt is not already fresh.
    await deps.cache.put("apns:jwt", { token: "stale", issuedAt: Math.floor(deps.now() / 1000) - 60, keyId: "KEYID12345", teamId: "TEAMID1234" });
    const outcome = await deliverApns(deps, URGENT, { token: DEVICE });
    expect(outcome.status).toBe("sent");
    expect(requests).toHaveLength(2);
    expect(requests[0].headers.get("authorization")).toBe("bearer stale");
    expect(requests[1].headers.get("authorization")).not.toBe("bearer stale");
  });
});

describe("APNs delivery", () => {
  it("does not call Apple when the key is missing", async () => {
    const { deps, requests } = await apple({}, { APNS_KEY_P8: undefined });
    expect(apnsConfigured(deps.env)).toBe(false);
    expect(await deliverApns(deps, URGENT, { token: DEVICE })).toEqual({ status: "skipped" });
    expect(requests).toEqual([]);
  });

  it("does not call Apple for a low-priority notice", async () => {
    const { deps, requests } = await apple({});
    expect(await deliverApns(deps, { ...URGENT, priority: "low" }, { token: DEVICE })).toEqual({ status: "skipped" });
    expect(requests).toEqual([]);
  });

  it("tries production first unless told otherwise", async () => {
    expect(defaultEnvironment({})).toBe("production");
    expect(defaultEnvironment({ APNS_USE_SANDBOX: "false" })).toBe("production");
    expect(defaultEnvironment({ APNS_USE_SANDBOX: "true" })).toBe("sandbox");
  });

  it("sends an alert for urgent and a silent wake for normal", async () => {
    const { deps, requests } = await apple({}, { APNS_BUNDLE_ID: "com.example.app" });
    await deliverApns(deps, URGENT, { token: DEVICE });
    await deliverApns(deps, { ...URGENT, priority: "normal" }, { token: DEVICE });
    const [alert, silent] = requests;
    expect(alert.path).toBe(`/3/device/${DEVICE}`);
    expect(alert.headers.get("apns-topic")).toBe("com.example.app");
    expect(alert.headers.get("apns-push-type")).toBe("alert");
    expect(alert.headers.get("apns-priority")).toBe("10");
    expect(JSON.parse(alert.body)).toMatchObject({ aps: { alert: { title: "Driver", body: "Gate is open" } }, id: "1" });
    expect(silent.headers.get("apns-push-type")).toBe("background");
    expect(silent.headers.get("apns-priority")).toBe("5");
    expect(JSON.parse(silent.body)).toMatchObject({ aps: { "content-available": 1 }, priority: "normal" });
  });

  it("uses the service the device named", async () => {
    const { deps, requests } = await apple({});
    const outcome = await deliverApns(deps, URGENT, { token: DEVICE, environment: "sandbox" });
    expect(outcome).toEqual({ status: "sent", environment: "sandbox" });
    expect(requests.map((request) => request.host)).toEqual(["api.sandbox.push.apple.com"]);
  });

  it("falls back to the other service when Apple says the token is bad", async () => {
    // A TestFlight build's token, while the relay is set to try sandbox first.
    const { deps, requests } = await apple(
      { "api.sandbox.push.apple.com": () => rejection(400, "BadDeviceToken") },
      { APNS_USE_SANDBOX: "true" },
    );
    const outcome = await deliverApns(deps, URGENT, { token: DEVICE });
    expect(outcome).toEqual({ status: "sent", environment: "production" });
    expect(requests.map((request) => request.host)).toEqual(["api.sandbox.push.apple.com", "api.push.apple.com"]);
  });

  it("reports a token that neither service accepts as gone", async () => {
    const { deps } = await apple({
      "api.push.apple.com": () => rejection(400, "BadDeviceToken"),
      "api.sandbox.push.apple.com": () => rejection(400, "BadDeviceToken"),
    });
    expect(await deliverApns(deps, URGENT, { token: DEVICE })).toEqual({ status: "failed", gone: true, reason: "BadDeviceToken" });
  });

  it("reports an unregistered device as gone without trying the other service", async () => {
    const { deps, requests } = await apple({ "api.push.apple.com": () => rejection(410, "Unregistered") });
    expect(await deliverApns(deps, URGENT, { token: DEVICE })).toEqual({ status: "failed", gone: true, reason: "Unregistered" });
    expect(requests).toHaveLength(1);
  });

  it("keeps the device after a failure that is not about its token", async () => {
    const { deps, requests } = await apple({ "api.push.apple.com": () => rejection(429, "TooManyRequests") });
    expect(await deliverApns(deps, URGENT, { token: DEVICE })).toEqual({ status: "failed", reason: "TooManyRequests" });
    expect(requests).toHaveLength(1);
  });

  it("reports a network failure as failed", async () => {
    const { deps } = await apple({});
    deps.send = async () => {
      throw new TypeError("network");
    };
    expect(await deliverApns(deps, URGENT, { token: DEVICE })).toEqual({ status: "failed", reason: "unreachable" });
  });
});
