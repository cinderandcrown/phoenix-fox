// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { refusal } from "./edge";
import type { ApnsEnvironment, PushDevice, PushNotice, PushOutcome } from "./apns";
import type { Mailbox } from "./mailbox";
import { botKey, deliver, targetsFor, type DeliveryResult, type WebhookConfig, type WebhookTarget } from "./webhooks";

export const MAX_BODY = 1_200_000;
const ASK_TTL_MS = 15 * 60 * 1000;
const INBOX_TTL_MS = 24 * 60 * 60 * 1000;
/** How long an ask stays out of `/pending` while its webhook is still being tried. */
const SENDING_GRACE_MS = 60 * 1000;
const MAX_DEVICES = 8;
const ALL_HANDS_REPLIES = 4;
const ASK_ID = /^[A-Za-z0-9._:-]{1,128}$/;
const LIMITS: Record<string, number> = {
  ask: 30,
  pending: 120,
  reply: 60,
  reply_poll: 180,
  push: 30,
  inbox: 40,
  device: 10,
  health: 30,
};

export interface Reply {
  text: string;
  from_bot: string;
}

/** Where an ask stands with one bot's webhook. */
export interface DeliveryRecord {
  state: "sending" | "delivered" | "failed";
  attempts: number;
  /** Last HTTP status from the bot, or 0 when there was none. */
  status: number;
  at: number;
}

export interface AskRecord {
  id: string;
  text: string;
  transcript: string;
  image?: string;
  images?: string[];
  timestamp: string;
  location?: unknown;
  context: unknown[];
  intent: string;
  target_bot: string;
  reply_to?: string;
  createdAt: number;
  status: "pending" | "ready";
  replies: Reply[];
  /** Webhook state by bot key. Absent when no webhook is configured for the ask. */
  deliveries?: Record<string, DeliveryRecord>;
}

export interface InboxRecord extends PushNotice {
  createdAt: number;
}

export interface DeviceRecord extends PushDevice {
  platform: string;
  updatedAt: number;
}

export interface RelayDeps {
  ownerToken: string;
  mailbox: Mailbox;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  /** Sends a push to one device. */
  notify: (notice: PushNotice, device: PushDevice) => Promise<PushOutcome>;
  /** Bot webhooks. An empty configuration leaves every ask to `/pending`. */
  webhooks: WebhookConfig;
  /** Outbound HTTP, for webhooks. */
  send: (request: Request) => Promise<Response>;
  /** Keeps work running after the response has gone out. */
  background: (work: Promise<unknown>) => void;
  /** Whether the APNs secrets are present, for `/health`. */
  apnsReady: boolean;
}

export async function handleRelay(request: Request, deps: RelayDeps): Promise<Response> {
  const refused = await refusal(request, deps.ownerToken, MAX_BODY);
  if (refused) return refused;

  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method.toUpperCase();
  const [head, tail] = parts;

  try {
    return await route(request, url, method, parts.length, head, tail, deps);
  } catch (error) {
    if (error instanceof BodyTooLarge) return json({ error: "body too large" }, 413);
    throw error;
  }
}

class BodyTooLarge extends Error {}

function route(
  request: Request,
  url: URL,
  method: string,
  depth: number,
  head: string,
  tail: string,
  deps: RelayDeps,
): Promise<Response> {
  if (depth === 1) {
    if (method === "POST" && head === "ask") return limit(deps, "ask", () => postAsk(request, url, deps));
    if (method === "GET" && head === "pending") return limit(deps, "pending", () => getPending(url, deps));
    if (method === "POST" && head === "push") return limit(deps, "push", () => postPush(request, deps));
    if (method === "GET" && head === "inbox") return limit(deps, "inbox", () => getInbox(url, deps));
    if (method === "POST" && head === "device") return limit(deps, "device", () => postDevice(request, deps));
    if (method === "GET" && head === "health") return limit(deps, "health", () => getHealth(deps));
  }
  if (depth === 2 && head === "reply") {
    if (method === "POST") return limit(deps, "reply", () => postReply(request, tail, deps));
    if (method === "GET") return limit(deps, "reply_poll", () => getReply(url, tail, deps));
  }
  return Promise.resolve(json({ error: "not found" }, 404));
}

// MARK: Phone

async function postAsk(request: Request, url: URL, deps: RelayDeps): Promise<Response> {
  const body = await readJson(request);
  if (!body) return json({ error: "expected json" }, 400);
  const id = stringField(body, "id");
  const text = stringField(body, "text");
  if (!id || !text) return json({ error: "id and text are required" }, 400);
  if (!ASK_ID.test(id)) return json({ error: "id must be 1 to 128 letters, digits, or . _ : -" }, 400);
  if (text.length > 8000) return json({ error: "text is too long" }, 400);

  const existing = await readAsk(deps, id);
  if (existing) return json({ id, status: existing.status, delivery: existing.deliveries ? "webhook" : "poll" }, 200);
  await sweep(deps);

  const record: AskRecord = {
    id,
    text,
    transcript: stringField(body, "transcript").slice(0, 16000),
    timestamp: stringField(body, "timestamp") || new Date(deps.now()).toISOString(),
    context: Array.isArray(body.context) ? body.context : [],
    intent: stringField(body, "intent") || "message",
    target_bot: stringField(body, "target_bot") || "Fire Fox",
    createdAt: deps.now(),
    status: "pending",
    replies: [],
  };
  if (typeof body.image === "string") record.image = body.image;
  if (Array.isArray(body.images)) record.images = body.images.filter((item): item is string => typeof item === "string");
  if (body.location !== undefined) record.location = body.location;
  const replyTo = stringField(body, "reply_to");
  if (replyTo) record.reply_to = replyTo;

  const targets = targetsFor(deps.webhooks, record.target_bot);
  if (targets.length > 0) {
    record.deliveries = {};
    for (const target of targets) {
      record.deliveries[botKey(target.bot)] = { state: "sending", attempts: 0, status: 0, at: deps.now() };
    }
  }
  await deps.mailbox.put(askKey(id), record);
  if (targets.length > 0) {
    const replyUrl = `${url.origin}/reply/${encodeURIComponent(id)}`;
    deps.background(Promise.all(targets.map((target) => sendAsk(record, target, replyUrl, deps))));
  }
  return json({ id, status: "pending", delivery: targets.length > 0 ? "webhook" : "poll" }, 202);
}

/** Posts the ask to one bot and records how that went. Never throws. */
async function sendAsk(ask: AskRecord, target: WebhookTarget, replyUrl: string, deps: RelayDeps): Promise<void> {
  let result: DeliveryResult;
  try {
    result = await deliver(target, "ask", { ask: publicAsk(ask), reply_url: replyUrl }, deps);
  } catch {
    result = { bot: target.bot, delivered: false, attempts: 0, status: 0 };
  }
  // The ask may have been answered or expired while the webhook was in flight, so read it again.
  const current = await readAsk(deps, ask.id);
  if (!current) return;
  current.deliveries = current.deliveries ?? {};
  current.deliveries[botKey(target.bot)] = {
    state: result.delivered ? "delivered" : "failed",
    attempts: result.attempts,
    status: result.status,
    at: deps.now(),
  };
  if (result.reply && current.status === "pending") {
    addReply(current, { text: result.reply, from_bot: target.bot }, false);
  }
  await deps.mailbox.put(askKey(current.id), current);
}

async function getReply(url: URL, id: string, deps: RelayDeps): Promise<Response> {
  const read = async () => {
    const ask = await readAsk(deps, id);
    if (!ask) return "missing" as const;
    return ask.status === "ready" ? ask : null;
  };
  const found = await waitFor(deps, waitSeconds(url), read);
  if (found === "missing") return json({ error: "unknown ask" }, 404);
  if (!found) return json({ id, status: "pending" }, 200);
  return json(readyBody(found), 200);
}

async function getInbox(url: URL, deps: RelayDeps): Promise<Response> {
  const wait = waitSeconds(url);
  const read = async () => {
    const messages = await inboxMessages(deps);
    return messages.length > 0 || wait === 0 ? messages : null;
  };
  const messages = (await waitFor(deps, wait, read)) ?? [];
  await Promise.all(messages.map((message) => deps.mailbox.delete(inboxKey(message.id))));
  return json({
    messages: messages.map(({ id, text, from_bot, priority }) => ({ id, text, from_bot, priority })),
  }, 200);
}

async function postDevice(request: Request, deps: RelayDeps): Promise<Response> {
  const body = await readJson(request);
  if (!body) return json({ error: "expected json" }, 400);
  const token = stringField(body, "token").toLowerCase();
  if (!/^[0-9a-f]{32,200}$/.test(token)) return json({ error: "token must be the APNs device token hex" }, 400);
  const environment = stringField(body, "environment");
  if (environment && environment !== "production" && environment !== "sandbox") {
    return json({ error: "environment must be production or sandbox" }, 400);
  }
  const record: DeviceRecord = { token, platform: stringField(body, "platform") || "ios", updatedAt: deps.now() };
  if (environment) record.environment = environment as ApnsEnvironment;
  await deps.mailbox.put(deviceKey(token), record);

  const devices = await devicesOf(deps);
  devices.sort((a, b) => b.updatedAt - a.updatedAt);
  await Promise.all(devices.slice(MAX_DEVICES).map((device) => deps.mailbox.delete(deviceKey(device.token))));
  return json({ status: "registered", devices: Math.min(devices.length, MAX_DEVICES) }, 200);
}

// MARK: Bots

async function getPending(url: URL, deps: RelayDeps): Promise<Response> {
  const wait = waitSeconds(url);
  const target = url.searchParams.get("target_bot")?.trim() ?? "";
  const everything = url.searchParams.get("include_delivered") === "1";
  const read = async () => {
    const asks = await pendingAsks(deps, target, everything);
    return asks.length > 0 || wait === 0 ? asks : null;
  };
  const found = await waitFor(deps, wait, read);
  return json({ asks: found ?? [] }, 200);
}

async function postReply(request: Request, id: string, deps: RelayDeps): Promise<Response> {
  // Read the body before the ask. Reading the ask first would leave a gap in which
  // another reply to the same ask could be stored and then overwritten.
  const body = await readJson(request);
  const ask = await readAsk(deps, id);
  if (!ask || expired(ask.createdAt, deps.now(), ASK_TTL_MS)) return json({ error: "unknown ask" }, 404);
  if (!body) return json({ error: "expected json" }, 400);
  const done = body.done === true;
  if (Array.isArray(body.replies)) {
    const replies = body.replies.flatMap(replyFrom);
    if (replies.length === 0) return json({ error: "replies need text and from_bot" }, 400);
    ask.replies = replies;
    if (done || !isAllHands(ask)) ask.status = "ready";
  } else {
    const one = replyFrom(body);
    if (one.length === 0) return json({ error: "text and from_bot are required" }, 400);
    addReply(ask, one[0], done);
  }
  await deps.mailbox.put(askKey(id), ask);
  return json(readyBody(ask), 200);
}

async function postPush(request: Request, deps: RelayDeps): Promise<Response> {
  const body = await readJson(request);
  if (!body) return json({ error: "expected json" }, 400);
  const text = stringField(body, "text");
  const fromBot = stringField(body, "from_bot");
  if (!text || !fromBot) return json({ error: "text and from_bot are required" }, 400);
  const priority = stringField(body, "priority") || "normal";
  if (priority !== "urgent" && priority !== "normal" && priority !== "low") {
    return json({ error: "priority must be urgent, normal, or low" }, 400);
  }
  const notice: InboxRecord = {
    id: crypto.randomUUID(),
    text: text.slice(0, 4000),
    from_bot: fromBot.slice(0, 64),
    priority,
    createdAt: deps.now(),
  };
  await sweep(deps);
  await deps.mailbox.put(inboxKey(notice.id), notice);
  const devices = await devicesOf(deps);
  if (devices.length === 0 || priority === "low") return json({ id: notice.id, status: "queued", apns: "skipped" }, 202);

  const outcomes = await Promise.all(devices.map((device) => pushTo(device, notice, deps)));
  const sent = outcomes.filter((status) => status === "sent").length;
  const failed = outcomes.filter((status) => status === "failed").length;
  const apns = sent === 0 ? (failed > 0 ? "failed" : "skipped") : failed > 0 ? "partial" : "sent";
  return json({ id: notice.id, status: "queued", apns }, 202);
}

/** Pushes to one device, then keeps what Apple said about its token. */
async function pushTo(device: DeviceRecord, notice: PushNotice, deps: RelayDeps): Promise<PushOutcome["status"]> {
  let outcome: PushOutcome;
  try {
    outcome = await deps.notify(notice, device);
  } catch {
    outcome = { status: "failed" };
  }
  if (outcome.gone) {
    await deps.mailbox.delete(deviceKey(device.token));
  } else if (outcome.environment && outcome.environment !== device.environment) {
    await deps.mailbox.put(deviceKey(device.token), { ...device, environment: outcome.environment });
  }
  return outcome.status;
}

// MARK: Status

async function getHealth(deps: RelayDeps): Promise<Response> {
  const devices = await devicesOf(deps);
  return json({
    ok: true,
    apns: deps.apnsReady,
    devices: devices.length,
    webhooks: deps.webhooks.targets.map((target) => target.bot),
    webhook_problems: deps.webhooks.problems,
  }, 200);
}

// MARK: Storage

/**
 * Removes asks and inbox messages that have outlived their time. It runs when something new
 * is stored, so the mailbox stays small even when no bot ever polls.
 */
async function sweep(deps: RelayDeps): Promise<void> {
  const now = deps.now();
  for (const key of await deps.mailbox.list("ask:")) {
    const ask = asAsk(await deps.mailbox.get(key));
    if (!ask || expired(ask.createdAt, now, ASK_TTL_MS)) await deps.mailbox.delete(key);
  }
  for (const key of await deps.mailbox.list("inbox:")) {
    const message = asInbox(await deps.mailbox.get(key));
    if (!message || expired(message.createdAt, now, INBOX_TTL_MS)) await deps.mailbox.delete(key);
  }
}

async function pendingAsks(deps: RelayDeps, target: string, everything: boolean): Promise<AskRecord[]> {
  const keys = await deps.mailbox.list("ask:");
  const key = botKey(target);
  const asks: AskRecord[] = [];
  for (const item of keys) {
    const ask = asAsk(await deps.mailbox.get(item));
    if (!ask || expired(ask.createdAt, deps.now(), ASK_TTL_MS)) continue;
    if (ask.status !== "pending") continue;
    if (key && key !== "all" && !isAllHands(ask) && botKey(ask.target_bot) !== key) continue;
    if (!everything && handedOver(ask, key, deps.now())) continue;
    asks.push(ask);
  }
  asks.sort((a, b) => a.createdAt - b.createdAt);
  return asks;
}

/**
 * Whether a webhook already gave this ask to the bot that is polling, or is still trying to.
 * A poll that names no bot is treated as the ask's own bot. An all-hands ask is never hidden
 * from such a poll, because the relay cannot tell which bot is asking.
 */
function handedOver(ask: AskRecord, pollKey: string, now: number): boolean {
  if (!ask.deliveries) return false;
  const named = pollKey && pollKey !== "all";
  if (!named && isAllHands(ask)) return false;
  const delivery = ask.deliveries[named ? pollKey : botKey(ask.target_bot)];
  if (!delivery) return false;
  if (delivery.state === "delivered") return true;
  return delivery.state === "sending" && now - delivery.at < SENDING_GRACE_MS;
}

async function inboxMessages(deps: RelayDeps): Promise<InboxRecord[]> {
  const keys = await deps.mailbox.list("inbox:");
  const messages: InboxRecord[] = [];
  for (const key of keys) {
    const message = asInbox(await deps.mailbox.get(key));
    if (!message || expired(message.createdAt, deps.now(), INBOX_TTL_MS)) continue;
    messages.push(message);
  }
  messages.sort((a, b) => a.createdAt - b.createdAt);
  return messages;
}

async function devicesOf(deps: RelayDeps): Promise<DeviceRecord[]> {
  const keys = await deps.mailbox.list("device:");
  const devices: DeviceRecord[] = [];
  for (const key of keys) {
    const device = asDevice(await deps.mailbox.get(key));
    if (device) devices.push(device);
  }
  return devices;
}

async function readAsk(deps: RelayDeps, id: string): Promise<AskRecord | null> {
  return asAsk(await deps.mailbox.get(askKey(id)));
}

// MARK: Rules

function isAllHands(ask: AskRecord): boolean {
  return botKey(ask.target_bot) === "all";
}

/** Adds one bot's reply. A single-bot ask is then ready; an all-hands ask waits for the team. */
function addReply(ask: AskRecord, reply: Reply, done: boolean): void {
  ask.replies.push(reply);
  if (!isAllHands(ask) || done || distinctBots(ask.replies) >= ALL_HANDS_REPLIES) ask.status = "ready";
}

function distinctBots(replies: Reply[]): number {
  return new Set(replies.map((reply) => botKey(reply.from_bot))).size;
}

/** The ask as a bot sees it in a webhook: what the phone sent, without the relay's bookkeeping. */
function publicAsk(ask: AskRecord): Record<string, unknown> {
  const { createdAt: _createdAt, status: _status, replies: _replies, deliveries: _deliveries, ...shown } = ask;
  return shown;
}

function readyBody(ask: AskRecord): Record<string, unknown> {
  return {
    id: ask.id,
    status: ask.status,
    text: ask.replies.map((reply) => reply.text).join(" "),
    from_bot: ask.replies[0]?.from_bot ?? "",
    replies: ask.replies,
    done: ask.status === "ready",
  };
}

function replyFrom(value: unknown): Reply[] {
  if (!value || typeof value !== "object") return [];
  const record = value as Record<string, unknown>;
  const text = stringField(record, "text");
  const fromBot = stringField(record, "from_bot");
  if (!text || !fromBot) return [];
  return [{ text: text.slice(0, 16000), from_bot: fromBot.slice(0, 64) }];
}

// MARK: Plumbing

async function limit(deps: RelayDeps, route: string, run: () => Promise<Response>): Promise<Response> {
  const minute = Math.floor(deps.now() / 60000);
  const key = `rl:${route}`;
  const stored = await deps.mailbox.get(key) as { minute?: number; count?: number } | undefined;
  const count = stored?.minute === minute ? (stored.count ?? 0) + 1 : 1;
  await deps.mailbox.put(key, { minute, count });
  if (count > (LIMITS[route] ?? 60)) {
    return Response.json({ error: "slow down" }, { status: 429, headers: { "retry-after": "60" } });
  }
  return run();
}

async function waitFor<T>(deps: RelayDeps, wait: number, read: () => Promise<T | null>): Promise<T | null> {
  const cap = Math.min(Math.max(wait, 0), 25);
  const deadline = deps.now() + cap * 1000;
  let found = await read();
  while (found === null && deps.now() < deadline) {
    await deps.sleep(Math.min(400, Math.max(deadline - deps.now(), 0)));
    found = await read();
  }
  return found;
}

function asAsk(value: unknown): AskRecord | null {
  if (!value || typeof value !== "object") return null;
  const record = value as AskRecord;
  if (typeof record.id !== "string" || !Array.isArray(record.replies)) return null;
  return record;
}

function asInbox(value: unknown): InboxRecord | null {
  if (!value || typeof value !== "object") return null;
  const record = value as InboxRecord;
  if (typeof record.id !== "string" || typeof record.text !== "string") return null;
  return record;
}

function asDevice(value: unknown): DeviceRecord | null {
  if (!value || typeof value !== "object") return null;
  const record = value as DeviceRecord;
  if (typeof record.token !== "string") return null;
  return record;
}

/** Parses a JSON object body. Throws `BodyTooLarge` once the body passes the size limit. */
async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  const text = await readText(request, MAX_BODY);
  try {
    const parsed = JSON.parse(text) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function readText(request: Request, limitBytes: number): Promise<string> {
  if (!request.body) return "";
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let size = 0;
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > limitBytes) {
      await reader.cancel().catch(() => {});
      throw new BodyTooLarge();
    }
    text += decoder.decode(value, { stream: true });
  }
  return text + decoder.decode();
}

function stringField(body: Record<string, unknown>, key: string): string {
  const value = body[key];
  return typeof value === "string" ? value.trim() : "";
}

function waitSeconds(url: URL): number {
  const raw = Number(url.searchParams.get("wait") ?? "0");
  if (!Number.isFinite(raw) || raw < 0) return 0;
  return raw;
}

function expired(createdAt: number, now: number, ttl: number): boolean {
  return now - createdAt > ttl;
}

function askKey(id: string): string {
  return `ask:${id}`;
}

function inboxKey(id: string): string {
  return `inbox:${id}`;
}

function deviceKey(token: string): string {
  return `device:${token}`;
}

function json(body: unknown, status: number): Response {
  return Response.json(body, { status });
}
