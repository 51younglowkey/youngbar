// SPDX-FileCopyrightText: 2026 YoungBar contributors
// SPDX-License-Identifier: GPL-3.0-only

// Cloudflare D1 stores only keyed hashes of random per-installation IDs.
// No IP, User-Agent, macOS account, machine identifiers, or menu-bar data
// are read or written by this application. The hosting provider still
// necessarily processes network connection metadata.
const DAY_MS = 24 * 60 * 60 * 1000;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const versionPattern = /^[a-zA-Z0-9.+_-]{1,32}$/;
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});
const dayOffset = (days) => new Date(Date.now() - days * DAY_MS).toISOString().slice(0, 10);

async function keyedHash(raw, secret) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(raw.toLowerCase()));
  return [...new Uint8Array(signature)].map(b => b.toString(16).padStart(2, "0")).join("");
}

async function parsePayload(request) {
  if (Number(request.headers.get("content-length") || 0) > 512) return null;
  const raw = await request.text();
  if (raw.length > 512) return null;
  let value;
  try { value = JSON.parse(raw); } catch { return null; }
  if (!value || typeof value !== "object"
      || typeof value.installation_id !== "string"
      || !uuidPattern.test(value.installation_id)
      || typeof value.app_version !== "string"
      || !versionPattern.test(value.app_version)) return null;
  return value;
}

async function receiveUsage(request, env) {
  const payload = await parsePayload(request);
  if (!payload) return json({ error: "Invalid payload" }, 400);
  const idHash = await keyedHash(payload.installation_id, env.HMAC_SECRET);
  const today = dayOffset(0);

  if (request.method === "DELETE") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM active_days WHERE installation_hash = ?").bind(idHash),
      env.DB.prepare("DELETE FROM installations WHERE installation_hash = ?").bind(idHash),
    ]);
    return json({ ok: true });
  }

  // D1 batch executes in one transaction. Repeated daily signals are idempotent.
  await env.DB.batch([
    env.DB.prepare(`INSERT INTO installations (installation_hash, version, first_seen, last_seen)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(installation_hash) DO UPDATE SET
                    version=excluded.version, last_seen=excluded.last_seen`)
      .bind(idHash, payload.app_version, today, today),
    env.DB.prepare("INSERT OR IGNORE INTO active_days (installation_hash, day) VALUES (?, ?)")
      .bind(idHash, today),
  ]);
  return json({ ok: true });
}

async function stats(env) {
  const [installations, activeToday, active7Days, active30Days, firstSeen30Days, versions] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS n FROM installations").first(),
    env.DB.prepare("SELECT COUNT(*) AS n FROM active_days WHERE day = ?").bind(dayOffset(0)).first(),
    env.DB.prepare("SELECT COUNT(DISTINCT installation_hash) AS n FROM active_days WHERE day >= ?")
      .bind(dayOffset(6)).first(),
    env.DB.prepare("SELECT COUNT(DISTINCT installation_hash) AS n FROM active_days WHERE day >= ?")
      .bind(dayOffset(29)).first(),
    env.DB.prepare("SELECT COUNT(*) AS n FROM installations WHERE first_seen >= ?")
      .bind(dayOffset(29)).first(),
    env.DB.prepare("SELECT version, COUNT(*) AS installations FROM installations GROUP BY version ORDER BY installations DESC").all(),
  ]);
  return json({
    date_utc: dayOffset(0),
    known_opted_in_installations: installations.n,
    active_today: activeToday.n,
    active_last_7_days: active7Days.n,
    active_last_30_days: active30Days.n,
    first_seen_last_30_days: firstSeen30Days.n,
    installed_versions: versions.results,
    note: "Counts represent consenting installation IDs, not distinct people or confirmed OS installations. Data is retained for at most 90 days after last use."
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === "/v1/usage" && ["POST", "DELETE"].includes(request.method)) {
        if (!env.HMAC_SECRET || !env.DB) return json({ error: "Service not configured" }, 503);
        return await receiveUsage(request, env);
      }
      if (url.pathname === "/v1/stats" && request.method === "GET") {
        if (!env.STATS_TOKEN || request.headers.get("authorization") !== `Bearer ${env.STATS_TOKEN}`) {
          return json({ error: "Unauthorized" }, 401);
        }
        return await stats(env);
      }
      return json({ error: "Not found" }, 404);
    } catch {
      // Do not log request headers or bodies.
      return json({ error: "Service unavailable" }, 503);
    }
  },

  async scheduled(_event, env) {
    // Retain daily activity for 30 days and installation records for 90
    // days since last usage signal. No raw UUIDs are stored server-side.
    const oldestActivity = dayOffset(29);
    const oldestInstallation = dayOffset(89);
    await env.DB.batch([
      env.DB.prepare("DELETE FROM active_days WHERE day < ?").bind(oldestActivity),
      env.DB.prepare("DELETE FROM active_days WHERE installation_hash IN (SELECT installation_hash FROM installations WHERE last_seen < ?)")
        .bind(oldestInstallation),
      env.DB.prepare("DELETE FROM installations WHERE last_seen < ?").bind(oldestInstallation),
    ]);
  },
};
