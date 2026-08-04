-- Ground to Growth Connect v0.1 schema (SQLite) — privacy-first location tracking

-- Reusable UUID-v4-like default expression for text primary keys.

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  person_type TEXT NOT NULL DEFAULT 'homeless'
    CHECK (person_type IN ('homeless', 'volunteer', 'employee', 'admin')),
  -- PII is encrypted at rest (AES-256-GCM); stored as BLOBs.
  name_encrypted BLOB NOT NULL,
  email_encrypted BLOB,
  gender_encrypted BLOB,
  phone_encrypted BLOB,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS consent_records (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consent_version TEXT NOT NULL,
  disclosure_text TEXT NOT NULL,
  granted INTEGER NOT NULL,
  granted_at TEXT,
  revoked_at TEXT,
  user_agent_hash TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_consent_records_user_created
  ON consent_records(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS location_reports (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  latitude_encrypted BLOB NOT NULL,
  longitude_encrypted BLOB NOT NULL,
  accuracy_meters REAL,
  reported_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_location_reports_user_reported
  ON location_reports(user_id, reported_at DESC);

CREATE INDEX IF NOT EXISTS idx_location_reports_reported_at
  ON location_reports(reported_at DESC);

-- View: latest consent status per user (SQLite has no DISTINCT ON)
CREATE VIEW IF NOT EXISTS user_consent_status AS
SELECT
  user_id,
  granted,
  consent_version,
  granted_at,
  revoked_at,
  last_recorded_at
FROM (
  SELECT
    user_id,
    granted,
    consent_version,
    granted_at,
    revoked_at,
    created_at AS last_recorded_at,
    -- Tie-break on rowid (monotonic insertion order), not id: id is a random
    -- UUID, so it carries no ordering information when two rows share the
    -- same created_at timestamp (easily possible at millisecond precision).
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, rowid DESC) AS rn
  FROM consent_records
)
WHERE rn = 1;
