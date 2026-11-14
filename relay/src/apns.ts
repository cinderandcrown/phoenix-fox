// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import type { RelayEnv } from "./env";
import type { Mailbox } from "./mailbox";

export interface PushNotice {
  id: string;
  text: string;
  from_bot: string;
  priority: "urgent" | "normal" | "low";
}

/**
 * Apple runs two push services and a device token works on only one of them.
 * A build installed from TestFlight or the App Store uses production.
 * A build run from Xcode uses sandbox.
 */
export type ApnsEnvironment = "production" | "sandbox";

export interface PushDevice {
  token: string;
  environment?: ApnsEnvironment;
}

export interface PushOutcome {
  status: "sent" | "skipped" | "failed";
  /** The service that accepted the token. The caller stores it for next time. */
  environment?: ApnsEnvironment;
  /** Apple says the token is no longer valid. The caller forgets the device. */
  gone?: boolean;
  /** Apple's reason string for a failure, for the log. */
  reason?: string;
}

export interface ApnsDeps {
  env: Pick<RelayEnv, "APNS_KEY_P8" | "APNS_KEY_ID" | "APPLE_TEAM_ID" | "APNS_BUNDLE_ID" | "APNS_USE_SANDBOX">;
  send: (request: Request) => Promise<Response>;
  now: () => number;
  /** Holds the provider token between pushes. */
  cache: Pick<Mailbox, "get" | "put" | "delete">;
}

const HOSTS: Record<ApnsEnvironment, string> = {
  production: "api.push.apple.com",
  sandbox: "api.sandbox.push.apple.com",
};
const JWT_KEY = "apns:jwt";
/** Apple rejects a provider token older than an hour and penalises one replaced within twenty minutes. */
const JWT_REUSE_SECONDS = 45 * 60;

interface CachedJwt {
  token: string;
  issuedAt: number;
  keyId: string;
  teamId: string;
}

export function apnsConfigured(env: Pick<RelayEnv, "APNS_KEY_P8" | "APNS_KEY_ID" | "APPLE_TEAM_ID">): boolean {
  return Boolean(env.APNS_KEY_P8 && env.APNS_KEY_ID && env.APPLE_TEAM_ID);
}

/** The service to try first for a device that has not said which one it uses. */
export function defaultEnvironment(env: Pick<RelayEnv, "APNS_USE_SANDBOX">): ApnsEnvironment {
  return env.APNS_USE_SANDBOX === "true" ? "sandbox" : "production";
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

/**
 * Sends one notice to one device.
 *
 * The device's own service is tried first. When Apple answers that the token is bad there,
 * the other service is tried, because that answer is what a token from the other service
 * gets. A push therefore reaches a TestFlight build and an Xcode build alike, whatever
 * `APNS_USE_SANDBOX` says.
 */
export async function deliverApns(deps: ApnsDeps, notice: PushNotice, device: PushDevice): Promise<PushOutcome> {
  if (notice.priority === "low") return { status: "skipped" };
  if (!apnsConfigured(deps.env)) return { status: "skipped" };
  const first = device.environment ?? defaultEnvironment(deps.env);
  const second: ApnsEnvironment = first === "production" ? "sandbox" : "production";

  let badEverywhere = true;
  let reason = "";
  for (const environment of [first, second]) {
    const result = await post(deps, notice, device.token, environment);
    if (result.ok) return { status: "sent", environment };
    reason = result.reason;
    if (result.status === 410) return { status: "failed", gone: true, reason };
    if (result.reason !== "BadDeviceToken") {
      badEverywhere = false;
      break;
    }
  }
  return badEverywhere ? { status: "failed", gone: true, reason } : { status: "failed", reason };
}

async function post(
  deps: ApnsDeps,
  notice: PushNotice,
  deviceToken: string,
  environment: ApnsEnvironment,
): Promise<{ ok: boolean; status: number; reason: string }> {
  const urgent = notice.priority === "urgent";
  const extra = { id: notice.id, from_bot: notice.from_bot, priority: notice.priority };
  const body = JSON.stringify(urgent
    ? { aps: { alert: { title: notice.from_bot, body: notice.text }, sound: "default" }, ...extra }
    : { aps: { "content-available": 1 }, ...extra });
  // A rejected provider token is replaced once. Any other answer is final for this service.
  for (const fresh of [false, true]) {
    let response: Response;
    try {
      response = await deps.send(new Request(`https://${HOSTS[environment]}/3/device/${deviceToken}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${await providerToken(deps, fresh)}`,
          "apns-topic": deps.env.APNS_BUNDLE_ID || "com.cinderandcrown.phoenixfox",
          "apns-push-type": urgent ? "alert" : "background",
          "apns-priority": urgent ? "10" : "5",
        },
        body,
      }));
    } catch {
      return { ok: false, status: 0, reason: "unreachable" };
    }
    if (response.ok) {
      await response.body?.cancel().catch(() => {});
      return { ok: true, status: response.status, reason: "" };
    }
    const reason = await reasonOf(response);
    const tokenRejected = response.status === 403 && (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken");
    if (!tokenRejected || fresh) return { ok: false, status: response.status, reason };
  }
  return { ok: false, status: 0, reason: "unreachable" };
}

async function providerToken(deps: ApnsDeps, fresh: boolean): Promise<string> {
  const keyId = deps.env.APNS_KEY_ID ?? "";
  const teamId = deps.env.APPLE_TEAM_ID ?? "";
  const nowSeconds = Math.floor(deps.now() / 1000);
  if (!fresh) {
    const cached = asCachedJwt(await deps.cache.get(JWT_KEY));
    const age = cached ? nowSeconds - cached.issuedAt : Infinity;
    if (cached && cached.keyId === keyId && cached.teamId === teamId && age >= 0 && age < JWT_REUSE_SECONDS) {
      return cached.token;
    }
  }
  const token = await apnsJwt(deps.env.APNS_KEY_P8 ?? "", keyId, teamId, nowSeconds);
  const record: CachedJwt = { token, issuedAt: nowSeconds, keyId, teamId };
  await deps.cache.put(JWT_KEY, record);
  return token;
}

function asCachedJwt(value: unknown): CachedJwt | null {
  if (!value || typeof value !== "object") return null;
  const record = value as CachedJwt;
  if (typeof record.token !== "string" || typeof record.issuedAt !== "number") return null;
  return record;
}

async function reasonOf(response: Response): Promise<string> {
  try {
    const parsed = await response.json() as { reason?: unknown };
    return typeof parsed.reason === "string" ? parsed.reason : "";
  } catch {
    return "";
  }
}
