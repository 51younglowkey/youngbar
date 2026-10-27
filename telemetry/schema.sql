-- YoungBar voluntary telemetry: keyed pseudonymous IDs only.
-- Raw UUIDs are never stored. The worker deletes records on opt-out.
CREATE TABLE IF NOT EXISTS installations (
  installation_hash TEXT PRIMARY KEY NOT NULL,
  version TEXT NOT NULL,
  first_seen TEXT NOT NULL,
  last_seen TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS active_days (
  installation_hash TEXT NOT NULL,
  day TEXT NOT NULL,
  PRIMARY KEY (installation_hash, day),
  FOREIGN KEY (installation_hash) REFERENCES installations (installation_hash) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS active_days_by_day ON active_days (day);
CREATE INDEX IF NOT EXISTS installations_by_last_seen ON installations (last_seen);
