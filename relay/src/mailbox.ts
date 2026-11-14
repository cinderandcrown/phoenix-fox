// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Cinder and Crown LLC

export interface Mailbox {
  get(key: string): Promise<unknown>;
  put(key: string, value: unknown): Promise<void>;
  delete(key: string): Promise<void>;
  list(prefix: string): Promise<string[]>;
}

export class MemoryMailbox implements Mailbox {
  private readonly rows = new Map<string, unknown>();

  async get(key: string): Promise<unknown> {
    return this.rows.get(key);
  }

  async put(key: string, value: unknown): Promise<void> {
    this.rows.set(key, value);
  }

  async delete(key: string): Promise<void> {
    this.rows.delete(key);
  }

  async list(prefix: string): Promise<string[]> {
    return [...this.rows.keys()].filter((key) => key.startsWith(prefix));
  }
}

export class DurableMailbox implements Mailbox {
  constructor(private readonly storage: DurableObjectStorage) {}

  async get(key: string): Promise<unknown> {
    return this.storage.get(key);
  }

  async put(key: string, value: unknown): Promise<void> {
    await this.storage.put(key, value);
  }

  async delete(key: string): Promise<void> {
    await this.storage.delete(key);
  }

  async list(prefix: string): Promise<string[]> {
    const listed = await this.storage.list({ prefix });
    return [...listed.keys()];
  }
}
