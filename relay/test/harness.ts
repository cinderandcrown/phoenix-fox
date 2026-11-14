import { handleRelay, type RelayDeps } from "../src/handle";
import { MemoryMailbox } from "../src/mailbox";
import type { PushDevice, PushOutcome } from "../src/apns";
import { NO_WEBHOOKS } from "../src/webhooks";

export const TOKEN = "owner-token";

export interface Sent {
  url: string;
  headers: Headers;
  body: string;
}

/**
 * A relay with a clock the test moves, an in-memory mailbox, and outbound HTTP that is
 * recorded and answered by `respond`. Background work is collected so a test can wait for it.
 */
export function harness(extra: Partial<RelayDeps> = {}, respond: (sent: Sent, index: number) => Response | Promise<Response> = () => new Response(null, { status: 204 })) {
  let now = 1_700_000_000_000;
  const mailbox = new MemoryMailbox();
  const pushes: PushDevice[] = [];
  const sent: Sent[] = [];
  const work: Promise<unknown>[] = [];
  const deps: RelayDeps = {
    ownerToken: TOKEN,
    mailbox,
    now: () => now,
    sleep: async (ms) => {
      now += ms;
    },
    notify: async (_notice, device): Promise<PushOutcome> => {
      pushes.push(device);
      return { status: "sent" };
    },
    webhooks: NO_WEBHOOKS,
    send: async (request) => {
      const record = { url: request.url, headers: request.headers, body: await request.text() };
      sent.push(record);
      return respond(record, sent.length - 1);
    },
    background: (promise) => {
      work.push(promise);
    },
    apnsReady: false,
    ...extra,
  };
  const call = (path: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    if (!headers.has("authorization")) headers.set("authorization", `Bearer ${TOKEN}`);
    return handleRelay(new Request(`https://relay.test${path}`, { ...init, headers }), deps);
  };
  const post = (path: string, body: unknown) => call(path, { method: "POST", body: JSON.stringify(body) });
  const read = async <T>(path: string) => (await call(path)).json() as Promise<T>;
  return {
    call,
    post,
    read,
    deps,
    mailbox,
    pushes,
    sent,
    /** Waits for webhook deliveries started so far. */
    settle: async () => {
      await Promise.all(work.splice(0));
    },
    advance: (ms: number) => {
      now += ms;
    },
    now: () => now,
  };
}
