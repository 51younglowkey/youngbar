# YoungBar voluntary usage statistics / 自愿使用统计

YoungBar runs fully offline by default. Telemetry requires **both** a deployed
service and an explicit opt-in from each user; existing v0.1.0 releases do not
contain this feature. Never enable telemetry automatically or silently.

YoungBar 默认完全离线运行。只有开发者先部署统计服务，且用户主动打开
「通用 → 隐私 → 分享匿名使用统计」后才会上报。现有 v0.1.0 Release 不受影响。

## What is measured / 统计口径

- **Known opted-in installations**: distinct consenting, random per-installation
  identifiers seen during the last 90 days. An identifier is created only after
  opt-in. Reinstalling or opting back in creates another countable installation.
- **Active today / 7 days / 30 days**: consenting installation IDs that sent
  at least one successful daily heartbeat in the stated UTC window.
- **Version distribution**: current app versions for those installation IDs.
- These are **not** download counts, guaranteed installs, unique humans, or
  all users. GitHub Release asset `download_count` is a separate metric.
- A single opted-in instance sends a POST on its first eligible launch and
  then at most once per UTC calendar day while running; the app checks
  periodically, but skips transmission once that day's request succeeds.
  If it is offline, the next eligible check may retry. Sending never blocks
  launch, UI or menu-bar functions.

## Data sent / 收集内容

The client POSTs JSON to its configured HTTPS endpoint:

```json
{"installation_id":"random-local-UUIDv4","app_version":"0.1.1"}
```

(The UUID above is an illustrative placeholder, not a real identifier.)

The UUID is randomly generated and stored only in local UserDefaults.
It is **pseudonymous**, not fully anonymous: it is stable while consent remains
enabled so the server can count one installation only once in each period.
It is **not** a hardware ID, Apple ID, email address, serial number, or MAC
address. YoungBar never sends menu-bar item names, app usage, keystrokes,
Accessibility data, screenshots, file paths, or diagnostic reports.

The server stores only an **HMAC-SHA256 keyed hash** of that random ID,
the app version, and UTC calendar dates. It does not persist the raw UUID,
IP address or User-Agent in the D1 database. The hosting/network provider
necessarily processes IP/network metadata to transmit requests; review its
own logging, retention and terms before deployment.

**Opt-out:** stopping telemetry immediately removes the local UUID and sends
a best-effort DELETE for all database rows associated with the former UUID.
Network failures mean deletion cannot be guaranteed immediately; the backend
also purges daily records older than 30 days and installation records that
have been inactive for 90 days. To delete rows reliably, users may need a
working network when they opt out, or developers may need a recovery process.
Users who never opt in never generate an ID or request.

## Deploy to Cloudflare (requires your own account)

This is an optional example backend, not a preconfigured production service.

1. Install Node.js and log in to your Cloudflare account:
   `cd telemetry && npx wrangler login`
2. Create the database: `npx wrangler d1 create youngbar-telemetry`
3. Copy `wrangler.toml.example` to `wrangler.toml` and replace
   `REPLACE_WITH_YOUR_REAL_D1_DATABASE_ID` with the returned database ID.
4. Apply the schema: `npx wrangler d1 execute youngbar-telemetry --remote --file=./schema.sql`
5. Create two independent high-entropy secrets:
   `npx wrangler secret put HMAC_SECRET` and
   `npx wrangler secret put STATS_TOKEN`.
   Use random values, for example generated with `openssl rand -hex 32`.
   **Never put these secrets in Git or the macOS application.**
6. Deploy: `npx wrangler deploy`. Record the HTTPS Worker URL.
7. In the root `Info.plist`, add a `YoungBarUsageEndpoint` string key
   containing `https://YOUR_WORKER_HOST/v1/usage`; replace the host with
   the deployed Worker hostname. Do not include `/v1/stats` in the app.
8. Run `sh Scripts/build.sh` on macOS with the project's configured toolchain.
   Validate the opt-in behavior and version, then distribute **a new Release**.
   Never replace the old asset silently.

Without the `YoungBarUsageEndpoint` bundle key (as in this branch),
the settings toggle is disabled and **no network requests** occur.

### Private stats / 查看统计

Get your Worker hostname from the deploy output, then locally run:

```sh
curl -sS -H "Authorization: Bearer $STATS_TOKEN" \
  "https://YOUR_WORKER_HOST/v1/stats"
```

The stats route requires the secret `STATS_TOKEN` and must not be embedded in
the app, README URLs, CI output, or public websites. The receiver endpoints
are public by design and can be spoofed or flooded; configure Cloudflare
rate-limiting/WAF controls if necessary and interpret counts as approximate.

### Checks before enabling a release / 发布验证

- Default OFF; check that a freshly installed app creates **no** ID and
  makes **no** telemetry requests.
- With backend missing, the toggle stays disabled. With backend configured,
  opt in and verify exactly one new ID and at most one successful daily POST.
- Verify toggling OFF deletes the local ID, requests server deletion, and
  blocks future POSTs. Exercise an in-flight POST/DELETE race as well.
- Verify a user can use YoungBar normally when networking is unavailable.
- Check that app version is correct and that the /v1/stats Bearer token is
  required, including negative tests.
- Build on **macOS 27 / Swift 6.3**. Do not claim the Linux environment builds
  or tests the AppKit application.
- Document the hosted endpoint, operator contact, privacy policy and any
  Cloudflare-side log retention before requesting users' consent.

本功能只提供客户端、后端源码和部署说明；在你部署服务、填写正式 URL、
通过 macOS 测试并发布新版前，**不会开始实际统计**。
