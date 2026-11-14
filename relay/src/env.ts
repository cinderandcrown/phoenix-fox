// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

export interface RelayEnv {
  RELAY: DurableObjectNamespace;
  /** The bearer every caller sends. */
  RELAY_TOKEN: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APPLE_TEAM_ID?: string;
  APNS_BUNDLE_ID?: string;
  /** "true" tries Apple's sandbox push service first for a device that has not said which it uses. */
  APNS_USE_SANDBOX?: string;
  /** JSON object from bot name to webhook URL, or to `{ "url", "secret"?, "headers"? }`. */
  BOT_WEBHOOKS?: string;
  /** Signs webhooks. When unset, `RELAY_TOKEN` signs them. */
  WEBHOOK_SECRET?: string;
}
