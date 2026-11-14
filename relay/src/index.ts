// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { refusal } from "./edge";
import type { RelayEnv } from "./env";
import { MAX_BODY } from "./handle";

export { RelayRoom } from "./room";

export default {
  async fetch(request: Request, env: RelayEnv): Promise<Response> {
    // A caller without the bearer is turned away here and never wakes the mailbox.
    const refused = await refusal(request, env.RELAY_TOKEN, MAX_BODY);
    if (refused) return refused;
    const room = env.RELAY.get(env.RELAY.idFromName("owner"));
    return room.fetch(request);
  },
} satisfies ExportedHandler<RelayEnv>;
