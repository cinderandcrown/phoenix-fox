// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { DurableObject } from "cloudflare:workers";
import { apnsConfigured, deliverApns } from "./apns";
import type { RelayEnv } from "./env";
import { handleRelay } from "./handle";
import { DurableMailbox } from "./mailbox";
import { parseWebhooks, type WebhookConfig } from "./webhooks";

export class RelayRoom extends DurableObject<RelayEnv> {
  private readonly mailbox: DurableMailbox;
  private readonly webhooks: WebhookConfig;

  constructor(ctx: DurableObjectState, env: RelayEnv) {
    super(ctx, env);
    this.mailbox = new DurableMailbox(ctx.storage);
    this.webhooks = parseWebhooks(env.BOT_WEBHOOKS, env.WEBHOOK_SECRET || env.RELAY_TOKEN);
    for (const problem of this.webhooks.problems) console.warn(`BOT_WEBHOOKS: ${problem}`);
  }

  async fetch(request: Request): Promise<Response> {
    const send = (outbound: Request) => fetch(outbound);
    const now = () => Date.now();
    return handleRelay(request, {
      ownerToken: this.env.RELAY_TOKEN,
      mailbox: this.mailbox,
      now,
      sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
      notify: (notice, device) => deliverApns({ env: this.env, send, now, cache: this.mailbox }, notice, device),
      webhooks: this.webhooks,
      send,
      background: (work) => this.ctx.waitUntil(work),
      apnsReady: apnsConfigured(this.env),
    });
  }
}
