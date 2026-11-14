// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { DurableObject } from "cloudflare:workers";
import { deliverApns } from "./apns";
import type { RelayEnv } from "./env";
import { handleRelay } from "./handle";
import { DurableMailbox } from "./mailbox";

export class RelayRoom extends DurableObject<RelayEnv> {
  constructor(ctx: DurableObjectState, env: RelayEnv) {
    super(ctx, env);
  }

  async fetch(request: Request): Promise<Response> {
    return handleRelay(request, {
      ownerToken: this.env.RELAY_TOKEN,
      mailbox: new DurableMailbox(this.ctx.storage),
      now: () => Date.now(),
      sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
      notify: (notice, deviceToken) => deliverApns(this.env, notice, deviceToken),
    });
  }
}
