// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

import { bearerMatches } from "./auth";

/**
 * The check every request passes before it reaches the mailbox.
 * Returns the response that turns the caller away, or null to let the request through.
 */
export async function refusal(request: Request, token: string | undefined, maxBody: number): Promise<Response | null> {
  if (!token) return Response.json({ error: "relay token is not configured" }, { status: 500 });
  if (!(await bearerMatches(request.headers.get("authorization"), token))) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  if (Number(request.headers.get("content-length") ?? "0") > maxBody) {
    return Response.json({ error: "body too large" }, { status: 413 });
  }
  return null;
}
