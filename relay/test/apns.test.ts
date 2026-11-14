import { describe, expect, it } from "vitest";
import { apnsConfigured, apnsJwt, deliverApns } from "../src/apns";
import type { RelayEnv } from "../src/env";

function decodePart(part: string): string {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
}

async function testKey(): Promise<{ pem: string; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", pair.privateKey);
  const bytes = new Uint8Array(pkcs8);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary)}\n-----END PRIVATE KEY-----\n`;
  return { pem, publicKey: pair.publicKey };
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

  it("does not call Apple when the key is missing", async () => {
    const env = { RELAY_TOKEN: "x" } as RelayEnv;
    expect(apnsConfigured(env)).toBe(false);
    const result = await deliverApns(env, { id: "1", text: "hi", from_bot: "Fire Fox", priority: "urgent" }, "aa".repeat(32));
    expect(result).toBe("skipped");
  });
});
