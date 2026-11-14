// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { bearerMatches } from "./auth";
import type { Mailbox } from "./mailbox";
import type { PushNotice } from "./apns";

const MAX_BODY = 1_200_000;
const ASK_TTL_MS = 15 * 60 * 1000;
const INBOX_TTL_MS = 24 * 60 * 60 * 1000;
const LIMITS: Record<string, number> = {
  ask: 30,
  pending: 120,
  reply: 60,
  reply_poll: 180,
  push: 30,
  inbox: 40,
  device: 10,
};

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
  replies: { text: string; from_bot: string }[];
}

export interface InboxRecord extends PushNotice {
  createdAt: number;
}

export interface DeviceRecord {
  token: string;
  platform: string;
  updatedAt: number;
}

export interface RelayDeps {
  ownerToken: string;
  mailbox: Mailbox;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  notify: (notice: PushNotice, deviceToken: string) => Promise<"sent" | "skipped" | "failed">;
}

export async function handleRelay(request: Request, deps: RelayDeps): Promise<Response> {
  if (!deps.ownerToken) return json({ error: "relay token is not configured" }, 500);
  const authed = await bearerMatches(request.headers.get("authorization"), deps.ownerToken);
  if (!authed) return json({ error: "unauthorized" }, 401);

  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY) return json({ error: "body too large" }, 413);

  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method.toUpperCase();

  if (method === "POST" && parts.length === 1 && parts[0] === "ask") {
    if (!(await allow(deps, "ask"))) return limited();
    return postAsk(request, deps);
  }
  if (method === "GET" && parts.length === 1 && parts[0] === "pending") {
    if (!(await allow(deps, "pending"))) return limited();
    return getPending(url, deps);
  }
  if (parts.length === 2 && parts[0] === "reply") {
    const route = method === "GET" ? "reply_poll" : "reply";
    if (!(await allow(deps, route))) return limited();
    if (method === "POST") return postReply(request, parts[1], deps);
    if (method === "GET") return getReply(url, parts[1], deps);
  }
  if (method === "POST" && parts.length === 1 && parts[0] === "push") {
    if (!(await allow(deps, "push"))) return limited();
    return postPush(request, deps);
  }
  if (method === "GET" && parts.length === 1 && parts[0] === "inbox") {
    if (!(await allow(deps, "inbox"))) return limited();
    return getInbox(url, deps);
  }
  if (method === "POST" && parts.length === 1 && parts[0] === "device") {
    if (!(await allow(deps, "device"))) return limited();
    return postDevice(request, deps);
  }
  return json({ error: "not found" }, 404);
}

async function postAsk(request: Request, deps: RelayDeps): Promise<Response> {
  const body = await readJson(request);
  if (!body) return json({ error: "expected json" }, 400);
  const id = stringField(body, "id");
  const text = stringField(body, "text");
  if (!id || !text) return json({ error: "id and text are required" }, 400);
  if (text.length > 8000) return json({ error: "text is too long" }, 400);
  const existing = await readAsk(deps, id);
  if (existing) return json({ id, status: existing.status }, 200);
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
  await deps.mailbox.put(askKey(id), record);
  return json({ id, status: "pending" }, 202);
}

async function getPending(url: URL, deps: RelayDeps): Promise<Response> {
  const wait = waitSeconds(url);
  const target = url.searchParams.get("target_bot")?.trim() ?? "";
  const read = async () => {
    const asks = await pendingAsks(deps, target);
    return asks.length > 0 || wait === 0 ? asks : null;
  };
  const found = await waitFor(deps, wait, read);
  return json({ asks: found ?? [] }, 200);
}

async function postReply(request: Request, id: string, deps: RelayDeps): Promise<Response> {
  const ask = await readAsk(deps, id);
  if (!ask || expired(ask.createdAt, deps.now(), ASK_TTL_MS)) return json({ error: "unknown ask" }, 404);
  const body = await readJson(request);
  if (!body) return json({ error: "expected json" }, 400);
  const done = body.done === true;
  if (Array.isArray(body.replies)) {
    const replies = body.replies.flatMap(replyFrom);
    if (replies.length === 0) return json({ error: "replies need text and from_bot" }, 400);
    ask.replies = replies;
    if (done || ask.target_bot !== "all") ask.status = "ready";
  } else {
    const one = replyFrom(body);
    if (one.length === 0) return json({ error: "text and from_bot are required" }, 400);
    ask.replies.push(one[0]);
    if (ask.target_bot !== "all" || done || distinctBots(ask.replies) >= 4) ask.status = "ready";
  }
  await deps.mailbox.put(askKey(id), ask);
  return json(readyBody(ask), 200);
}

async function getReply(url: URL, id: string, deps: RelayDeps): Promise<Response> {
  const wait = waitSeconds(url);
  const read = async () => {
    const ask = await readAsk(deps, id);
    if (!ask) return "missing" as const;
    if (ask.status === "ready") return ask;
    return null;
  };
  const found = await waitFor(deps, wait, read);
  if (found === "missing" || !found) {
    const ask = await readAsk(deps, id);
    if (!ask) return json({ error: "unknown ask" }, 404);
    return json({ id, status: "pending" }, 200);
  }
  return json(readyBody(found), 200);
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
  await deps.mailbox.put(inboxKey(notice.id), notice);
  const devices = await devicesOf(deps);
  if (devices.length === 0 || priority === "low") return json({ id: notice.id, status: "queued", apns: "skipped" }, 202);
  const results = await Promise.all(devices.map((device) => deps.notify(notice, device.token)));
  const sent = results.filter((item) => item === "sent").length;
  const failed = results.filter((item) => item === "failed").length;
  const apns = sent === 0 ? (failed > 0 ? "failed" : "skipped") : failed > 0 ? "partial" : "sent";
  return json({ id: notice.id, status: "queued", apns }, 202);
}

async function getInbox(url: URL, deps: RelayDeps): Promise<Response> {
  const wait = waitSeconds(url);
  const read = async () => {
    const messages = await inboxMessages(deps);
    return messages.length > 0 || wait === 0 ? messages : null;
  };
  const found = await waitFor(deps, wait, read);
  const messages = found ?? [];
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
  const platform = stringField(body, "platform") || "ios";
  const record: DeviceRecord = { token, platform, updatedAt: deps.now() };
  await deps.mailbox.put(deviceKey(token), record);
  const devices = await devicesOf(deps);
  return json({ status: "registered", devices: devices.length }, 200);
}

async function pendingAsks(deps: RelayDeps, target: string): Promise<AskRecord[]> {
  const keys = await deps.mailbox.list("ask:");
  const asks: AskRecord[] = [];
  for (const key of keys) {
    const ask = asAsk(await deps.mailbox.get(key));
    if (!ask) continue;
    if (expired(ask.createdAt, deps.now(), ASK_TTL_MS)) {
      await deps.mailbox.delete(key);
      continue;
    }
    if (ask.status !== "pending") continue;
    if (target && ask.target_bot !== target && ask.target_bot !== "all" && target !== "all") continue;
    asks.push(ask);
  }
  asks.sort((a, b) => a.createdAt - b.createdAt);
  return asks;
}

async function inboxMessages(deps: RelayDeps): Promise<InboxRecord[]> {
  const keys = await deps.mailbox.list("inbox:");
  const messages: InboxRecord[] = [];
  for (const key of keys) {
    const message = asInbox(await deps.mailbox.get(key));
    if (!message) continue;
    if (expired(message.createdAt, deps.now(), INBOX_TTL_MS)) {
      await deps.mailbox.delete(key);
      continue;
    }
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

async function allow(deps: RelayDeps, route: string): Promise<boolean> {
  const minute = Math.floor(deps.now() / 60000);
  const key = `rl:${route}:${minute}`;
  const count = Number(await deps.mailbox.get(key) ?? 0) + 1;
  await deps.mailbox.put(key, count);
  const old = await deps.mailbox.list("rl:");
  for (const item of old) {
    const stamp = Number(item.split(":").pop());
    if (minute - stamp > 2) await deps.mailbox.delete(item);
  }
  return count <= (LIMITS[route] ?? 60);
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

function readyBody(ask: AskRecord): Record<string, unknown> {
  const first = ask.replies[0];
  return {
    id: ask.id,
    status: ask.status,
    text: ask.replies.map((reply) => reply.text).join(" "),
    from_bot: first?.from_bot ?? "",
    replies: ask.replies,
    done: ask.status === "ready",
  };
}

function replyFrom(value: unknown): { text: string; from_bot: string }[] {
  if (!value || typeof value !== "object") return [];
  const record = value as Record<string, unknown>;
  const text = stringField(record, "text");
  const fromBot = stringField(record, "from_bot");
  if (!text || !fromBot) return [];
  return [{ text, from_bot: fromBot }];
}

function distinctBots(replies: { from_bot: string }[]): number {
  return new Set(replies.map((reply) => reply.from_bot)).size;
}

async function readAsk(deps: RelayDeps, id: string): Promise<AskRecord | null> {
  return asAsk(await deps.mailbox.get(askKey(id)));
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

async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text();
  if (text.length > MAX_BODY) return null;
  try {
    const parsed = JSON.parse(text) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
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

function limited(): Response {
  return Response.json({ error: "slow down" }, { status: 429, headers: { "retry-after": "60" } });
}
