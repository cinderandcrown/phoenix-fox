// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

export interface RelayEnv {
  RELAY: DurableObjectNamespace;
  RELAY_TOKEN: string;
  APNS_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APPLE_TEAM_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_USE_SANDBOX?: string;
}
