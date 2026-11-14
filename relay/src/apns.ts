// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import type { RelayEnv } from "./env";

export interface PushNotice {
  id: string;
  text: string;
  from_bot: string;
  priority: "urgent" | "normal" | "low";
}

export function apnsConfigured(env: Pick<RelayEnv, "APNS_KEY_P8" | "APNS_KEY_ID" | "APPLE_TEAM_ID">): boolean {
  return Boolean(env.APNS_KEY_P8 && env.APNS_KEY_ID && env.APPLE_TEAM_ID);
}

export function pemToPkcs8(pem: string): ArrayBuffer {
  const b64 = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export async function importApnsKey(pem: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function jsonBytes(value: unknown): Uint8Array {
  return new TextEncoder().encode(JSON.stringify(value));
}

/** ES256 JWT for APNs token auth. WebCrypto's ECDSA signature is already R||S. */
export async function apnsJwt(pem: string, keyId: string, teamId: string, nowSeconds: number): Promise<string> {
  const key = await importApnsKey(pem);
  const header = b64url(jsonBytes({ alg: "ES256", kid: keyId }));
  const claims = b64url(jsonBytes({ iss: teamId, iat: nowSeconds }));
  const unsigned = `${header}.${claims}`;
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned)),
  );
  return `${unsigned}.${b64url(signature)}`;
}

export async function deliverApns(env: RelayEnv, notice: PushNotice, deviceToken: string): Promise<"sent" | "skipped" | "failed"> {
  if (notice.priority === "low") return "skipped";
  if (!apnsConfigured(env) || !env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APPLE_TEAM_ID) return "skipped";
  const host = env.APNS_USE_SANDBOX === "false" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const token = await apnsJwt(env.APNS_KEY_P8, env.APNS_KEY_ID, env.APPLE_TEAM_ID, Math.floor(Date.now() / 1000));
  const urgent = notice.priority === "urgent";
  const body = urgent
    ? { aps: { alert: { title: notice.from_bot, body: notice.text }, sound: "default" }, id: notice.id, from_bot: notice.from_bot, priority: notice.priority }
    : { aps: { "content-available": 1 }, id: notice.id, from_bot: notice.from_bot, priority: notice.priority };
  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${token}`,
      "apns-topic": env.APNS_BUNDLE_ID || "com.cinderandcrown.phoenixfox",
      "apns-push-type": urgent ? "alert" : "background",
      "apns-priority": urgent ? "10" : "5",
    },
    body: JSON.stringify(body),
  });
  return response.ok ? "sent" : "failed";
}
