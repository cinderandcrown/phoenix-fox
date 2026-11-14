// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

/**
 * Outbound delivery of asks to bots.
 *
 * A bot that has a webhook does not need to poll `/pending`. The relay posts each ask to
 * the bot's URL, signed so the bot can tell the request came from this relay and was not
 * replayed. A delivery that fails leaves the ask in `/pending`, where a poll still finds it.
 */

export interface WebhookTarget {
  /** The bot's name as the owner wrote it in the configuration. */
  bot: string;
  url: string;
  /** HMAC key for this bot. */
  secret: string;
}

export interface WebhookConfig {
  targets: WebhookTarget[];
  /** What is wrong with the configuration. Never contains a URL or a secret. */
  problems: string[];
}

export interface DeliveryDeps {
  send: (request: Request) => Promise<Response>;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
}

export interface DeliveryResult {
  bot: string;
  delivered: boolean;
  attempts: number;
  /** Last HTTP status, or 0 when the request never got a response. */
  status: number;
  /** Text the bot returned in the webhook response, when it answered on the spot. */
  reply?: string;
}

export const SIGNATURE_HEADER = "x-relay-signature";
export const TIMESTAMP_HEADER = "x-relay-timestamp";
export const DELIVERY_HEADER = "x-relay-delivery";
export const EVENT_HEADER = "x-relay-event";

const USER_AGENT = "PhoenixFoxRelay/1 (+https://github.com/cinderandcrown/phoenix-fox)";
const ATTEMPT_TIMEOUT_MS = 10_000;
/** Wait before each attempt. Three attempts span about five seconds. */
const BACKOFF_MS = [0, 1_000, 4_000];
const MAX_REPLY_BYTES = 64_000;

export const NO_WEBHOOKS: WebhookConfig = { targets: [], problems: [] };

/** Bot names are matched without regard to case or surrounding space. */
export function botKey(name: string): string {
  return name.trim().toLowerCase();
}

/**
 * Reads `BOT_WEBHOOKS`: a JSON object from bot name to a URL, or to `{ "url", "secret" }`
 * when that bot signs with its own key. `sharedSecret` signs for every bot without one.
 */
export function parseWebhooks(raw: string | undefined, sharedSecret: string): WebhookConfig {
  if (!raw || !raw.trim()) return NO_WEBHOOKS;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { targets: [], problems: ["BOT_WEBHOOKS is not valid JSON"] };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { targets: [], problems: ["BOT_WEBHOOKS must be a JSON object of bot name to URL"] };
  }
  const targets: WebhookTarget[] = [];
  const problems: string[] = [];
  const seen = new Set<string>();
  for (const [name, value] of Object.entries(parsed as Record<string, unknown>)) {
    const bot = name.trim();
    const key = botKey(bot);
    if (!key || key === "all") {
      problems.push(`"${name}" is not a bot name`);
      continue;
    }
    if (seen.has(key)) {
      problems.push(`${bot}: listed more than once`);
      continue;
    }
    const entry = entryOf(value);
    if (!entry) {
      problems.push(`${bot}: expected a URL or { "url", "secret" }`);
      continue;
    }
    const fault = urlFault(entry.url);
    if (fault) {
      problems.push(`${bot}: ${fault}`);
      continue;
    }
    const secret = entry.secret || sharedSecret;
    if (!secret) {
      problems.push(`${bot}: no signing secret`);
      continue;
    }
    seen.add(key);
    targets.push({ bot, url: entry.url, secret });
  }
  return { targets, problems };
}

/** The webhooks an ask goes to: every configured bot for `all`, otherwise the named one. */
export function targetsFor(config: WebhookConfig, targetBot: string): WebhookTarget[] {
  const key = botKey(targetBot);
  if (key === "all") return config.targets;
  return config.targets.filter((target) => botKey(target.bot) === key);
}

/** Hex HMAC-SHA256 of `"<timestamp>.<body>"`. The timestamp is in the signed text so a captured request goes stale. */
export async function sign(secret: string, timestamp: number, body: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${body}`)));
  let hex = "";
  for (const byte of mac) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

/**
 * Posts one event to one bot, retrying a failure that could be temporary.
 * Every attempt carries the same delivery id, so a bot that sees it twice can ignore the repeat.
 */
export async function deliver(
  target: WebhookTarget,
  event: string,
  payload: Record<string, unknown>,
  deps: DeliveryDeps,
): Promise<DeliveryResult> {
  const delivery = crypto.randomUUID();
  const body = JSON.stringify({ event, delivery, bot: target.bot, ...payload });
  let status = 0;
  let attempts = 0;
  for (const delay of BACKOFF_MS) {
    if (delay > 0) await deps.sleep(delay);
    attempts += 1;
    const timestamp = Math.floor(deps.now() / 1000);
    const signature = await sign(target.secret, timestamp, body);
    let response: Response;
    try {
      response = await deps.send(new Request(target.url, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "user-agent": USER_AGENT,
          [EVENT_HEADER]: event,
          [DELIVERY_HEADER]: delivery,
          [TIMESTAMP_HEADER]: String(timestamp),
          [SIGNATURE_HEADER]: `v1=${signature}`,
        },
        body,
        // A redirect could carry the ask to a host the owner never named.
        redirect: "manual",
        signal: AbortSignal.timeout(ATTEMPT_TIMEOUT_MS),
      }));
    } catch {
      status = 0;
      continue;
    }
    status = response.status;
    if (response.ok) {
      const reply = await inlineReply(response);
      return reply ? { bot: target.bot, delivered: true, attempts, status, reply } : { bot: target.bot, delivered: true, attempts, status };
    }
    await response.body?.cancel().catch(() => {});
    if (!temporary(status)) break;
  }
  return { bot: target.bot, delivered: false, attempts, status };
}

function entryOf(value: unknown): { url: string; secret: string } | null {
  if (typeof value === "string") return { url: value.trim(), secret: "" };
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (typeof record.url !== "string") return null;
  if (record.secret !== undefined && typeof record.secret !== "string") return null;
  return { url: record.url.trim(), secret: (record.secret ?? "").trim() };
}

function urlFault(text: string): string | null {
  let url: URL;
  try {
    url = new URL(text);
  } catch {
    return "url is not valid";
  }
  // Plain http is accepted only for this machine, so a bot can be tried under `wrangler dev`.
  const loopback = url.hostname === "localhost" || url.hostname === "127.0.0.1" || url.hostname === "[::1]";
  if (url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) return "url must be https";
  if (url.username || url.password) return "url must not carry a user name or password";
  return null;
}

function temporary(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

/** A bot may answer in the webhook response with `{ "text": "..." }` instead of calling `/reply`. */
async function inlineReply(response: Response): Promise<string> {
  const type = response.headers.get("content-type") ?? "";
  if (!type.toLowerCase().includes("json")) {
    await response.body?.cancel().catch(() => {});
    return "";
  }
  try {
    const text = await response.text();
    if (text.length > MAX_REPLY_BYTES) return "";
    const parsed = JSON.parse(text) as unknown;
    if (!parsed || typeof parsed !== "object") return "";
    const reply = (parsed as Record<string, unknown>).text;
    return typeof reply === "string" ? reply.trim() : "";
  } catch {
    return "";
  }
}
