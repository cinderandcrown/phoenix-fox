// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import type { RelayEnv } from "./env";

export { RelayRoom } from "./room";

export default {
  async fetch(request: Request, env: RelayEnv): Promise<Response> {
    if (!env.RELAY_TOKEN) {
      return Response.json({ error: "relay token is not configured" }, { status: 500 });
    }
    const room = env.RELAY.get(env.RELAY.idFromName("owner"));
    return room.fetch(request);
  },
} satisfies ExportedHandler<RelayEnv>;
