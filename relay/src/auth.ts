// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

/** SHA-256 both sides, then compare the equal-length digests without an early exit. */
export async function bearerMatches(header: string | null, secret: string): Promise<boolean> {
  if (!secret) return false;
  const presented = bearerValue(header);
  if (!presented) return false;
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(secret)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let mismatch = 0;
  for (let i = 0; i < a.length; i++) mismatch |= a[i] ^ b[i];
  return mismatch === 0;
}

export function bearerValue(header: string | null): string {
  if (!header) return "";
  const match = /^Bearer\s+(\S+)\s*$/i.exec(header);
  return match?.[1] ?? "";
}
