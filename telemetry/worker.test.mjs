import assert from "node:assert/strict";
import { test } from "node:test";
import { webcrypto } from "node:crypto";
import worker from "./worker.js";

globalThis.crypto ??= webcrypto;

const base = "https://example.workers.dev";
const id = "2b0a9de2-c82d-43dc-a88f-aa1ee1cc600b";

function fixture() {
  const batches = [];
  const DB = {
    prepare(query) {
      return {
        query, values: [],
        bind(...values) { this.values = values; return this; },
        async first() { return { n: 0 }; },
        async all() { return { results: [] }; },
      };
    },
    async batch(statements) { batches.push(statements); return []; },
  };
  return { env: { HMAC_SECRET: "test-hmac-secret", STATS_TOKEN: "test-admin-token", DB }, batches };
}

function request(method, path, payload) {
  const settings = { method };
  if (payload) {
    settings.body = JSON.stringify(payload);
    settings.headers = { "content-type": "application/json" };
  }
  return new Request(base + path, settings);
}

test("statistics are admin-only", async () => {
  const { env } = fixture();
  const response = await worker.fetch(request("GET", "/v1/stats"), env);
  assert.equal(response.status, 401);
});

test("invalid client identifiers are rejected without database writes", async () => {
  const { env, batches } = fixture();
  const response = await worker.fetch(
    request("POST", "/v1/usage", { installation_id: "serial-number", app_version: "0.1.1" }), env
  );
  assert.equal(response.status, 400);
  assert.equal(batches.length, 0);
});

test("receiving a heartbeat hashes the random ID and inserts idempotent rows", async () => {
  const { env, batches } = fixture();
  const response = await worker.fetch(
    request("POST", "/v1/usage", { installation_id: id, app_version: "0.1.1" }), env
  );
  assert.equal(response.status, 200);
  assert.equal(batches.length, 1);
  assert.equal(batches[0].length, 2);
  const hash = batches[0][0].values[0];
  assert.match(hash, /^[a-f0-9]{64}$/);
  assert.notEqual(hash, id);
  assert.equal(batches[0][1].values[0], hash);
  assert.match(batches[0][1].query, /INSERT OR IGNORE/i);
});

test("opt-out requests remove daily activity and installation rows", async () => {
  const { env, batches } = fixture();
  const response = await worker.fetch(
    request("DELETE", "/v1/usage", { installation_id: id, app_version: "0.1.1" }), env
  );
  assert.equal(response.status, 200);
  assert.equal(batches[0].length, 2);
  assert.match(batches[0][0].query, /^DELETE FROM active_days/i);
  assert.match(batches[0][1].query, /^DELETE FROM installations/i);
  assert.equal(batches[0][0].values[0], batches[0][1].values[0]);
});

test("missing HMAC configuration prevents usage writes", async () => {
  const { env, batches } = fixture();
  delete env.HMAC_SECRET;
  const response = await worker.fetch(
    request("POST", "/v1/usage", { installation_id: id, app_version: "0.1.1" }), env
  );
  assert.equal(response.status, 503);
  assert.equal(batches.length, 0);
});
