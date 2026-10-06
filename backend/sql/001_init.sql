-- Ground to Growth Connect v0.1 schema (SQLite) — privacy-first location tracking
-- and secure document storage.

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
    CHECK (person_type IN ('homeless', 'volunteer', 'admin')),
  -- PII is encrypted at rest (AES-256-GCM); stored as BLOBs.
  name_encrypted BLOB NOT NULL,
  email_encrypted BLOB,
  gender_encrypted BLOB,
  phone_encrypted BLOB,
  -- Optional profile picture: the image itself is encrypted and lives in the
  -- blob store (same as documents); only its key and mime type are kept here.
  -- Older databases get these columns via dbstore.Migrate.
  profile_picture_key TEXT,
  profile_picture_mime TEXT,
  token_hash TEXT NOT NULL UNIQUE,
  -- Hash of the recovery code shown once at sign-up; lets someone who lost
  -- their phone (or changed numbers) get back into this same account from a
  -- new device. Older databases get this via dbstore.Migrate.
  recovery_code_hash TEXT,
  -- New volunteers start unapproved: until an admin approves them they can't
  -- see requests, locations or message anyone. Older databases get both
  -- columns via dbstore.Migrate (existing staff stay approved).
  volunteer_approved INTEGER NOT NULL DEFAULT 1,
  -- An admin can switch someone's messaging off outright.
  messaging_disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- consent_type distinguishes independent consent flows: sharing location vs.
-- storing identity documents are different decisions with different risk, so
-- a participant can grant one without the other.
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
  consent_type TEXT NOT NULL DEFAULT 'location_sharing'
    CHECK (consent_type IN ('location_sharing', 'document_storage')),
  consent_version TEXT NOT NULL,
  disclosure_text TEXT NOT NULL,
  granted INTEGER NOT NULL,
  granted_at TEXT,
  revoked_at TEXT,
  user_agent_hash TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_consent_records_user_type_created
  ON consent_records(user_id, consent_type, created_at DESC);

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

-- Scanned identity documents. Only ever readable by the owning user — there
-- is deliberately no query path that lets staff read storage_key (and even
-- with it, the blob store only ever holds encrypted bytes); staff may only
-- learn a document of some type exists (see handlers), never its content.
CREATE TABLE IF NOT EXISTS documents (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  document_type TEXT NOT NULL
    CHECK (document_type IN ('government_id', 'social_security_card', 'birth_certificate', 'other')),
  label TEXT,
  mime_type TEXT NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'application/pdf')),
  -- The encrypted file itself lives in blob storage (Backblaze B2, or a
  -- local directory in dev) — this is just the key it's stored under.
  storage_key TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_documents_user_created
  ON documents(user_id, created_at DESC);

-- Immutable log of every time a document's content was actually decrypted
-- and returned. Since only the owner can ever access their own documents,
-- this is a security/forensics trail (e.g. "was this token used from
-- somewhere unexpected"), not an access-control mechanism.
CREATE TABLE IF NOT EXISTS document_access_log (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  accessed_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- View: latest consent status per (user, consent_type) (SQLite has no DISTINCT ON)
CREATE VIEW IF NOT EXISTS user_consent_status AS
SELECT
  user_id,
  consent_type,
  granted,
  consent_version,
  granted_at,
  revoked_at,
  last_recorded_at
FROM (
  SELECT
    user_id,
    consent_type,
    granted,
    consent_version,
    granted_at,
    revoked_at,
    created_at AS last_recorded_at,
    -- Tie-break on rowid (monotonic insertion order), not id: id is a random
    -- UUID, so it carries no ordering information when two rows share the
    -- same created_at timestamp (easily possible at millisecond precision).
    ROW_NUMBER() OVER (PARTITION BY user_id, consent_type ORDER BY created_at DESC, rowid DESC) AS rn
  FROM consent_records
)
WHERE rn = 1;

-- Pages the Resources tab points to, checked now and then so an admin hears
-- about a page that has vanished or changed. See internal/freshness.
CREATE TABLE IF NOT EXISTS source_checks (
  url TEXT PRIMARY KEY,
  status INTEGER NOT NULL DEFAULT 0,      -- HTTP status, or 0 if unreachable
  error TEXT,
  content_hash TEXT,                       -- fingerprint of the page text at the last good check
  reviewed_hash TEXT,                      -- the fingerprint a person last signed off on
  acknowledged_status INTEGER,             -- an error status a person has seen and accepted
  checked_at TEXT NOT NULL,
  first_checked_at TEXT NOT NULL
);

-- A participant's own appointments (case worker meetings, ID appointments,
-- etc.), private to them alone — unlike location or documents, staff have no
-- visibility into this table at all, by design.
CREATE TABLE IF NOT EXISTS appointments (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title_encrypted BLOB NOT NULL,
  notes_encrypted BLOB,
  location_encrypted BLOB,
  starts_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_appointments_user_starts
  ON appointments(user_id, starts_at);

-- What a participant has asked for help with ("a ride", "ID help"...). Unlike
-- appointments, staff can see these: that is the point of posting one. A
-- volunteer "claims" a request to say they're on it. An appointment is only
-- visible to staff if the participant attached it to a request.
CREATE TABLE IF NOT EXISTS help_requests (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL
    CHECK (category IN ('food', 'shelter', 'ride', 'documents', 'clothing', 'health', 'work', 'other')),
  note_encrypted BLOB,
  appointment_id TEXT REFERENCES appointments(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'claimed', 'done')),
  claimed_by TEXT REFERENCES users(id) ON DELETE SET NULL,
  claimed_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_help_requests_user ON help_requests(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_help_requests_status ON help_requests(status, created_at);

-- One-to-one chat between a participant and the staff member helping them (or
-- the Ground to Growth team). Encrypted at rest; deleted with either account.
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  sender_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body_encrypted BLOB NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  read_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_messages_pair ON messages(sender_id, recipient_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_inbox ON messages(recipient_id, read_at);

-- A person getting support can block someone; neither can message the other
-- afterwards and the blocked volunteer no longer sees their requests.
CREATE TABLE IF NOT EXISTS blocks (
  blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (blocker_id, blocked_id)
);

-- "Report a problem": anyone can flag a person, and admins review them.
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY DEFAULT (
    lower(hex(randomblob(4))) || '-' ||
    lower(hex(randomblob(2))) || '-4' ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    substr('89ab', abs(random()) % 4 + 1, 1) ||
    substr(lower(hex(randomblob(2))), 2) || '-' ||
    lower(hex(randomblob(6)))
  ),
  reporter_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason_encrypted BLOB,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  resolved_at TEXT,
  resolved_by TEXT REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_reports_status ON reports(status, created_at);

-- Every time an admin opens someone's conversation. Messages are private to
-- the two people in them unless an admin reviews them for safety, and this is
-- the record that says who looked and when.
CREATE TABLE IF NOT EXISTS message_access_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  user_a TEXT NOT NULL,
  user_b TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

-- Phones that should get a notification for this person. A token belongs to
-- one phone, so when someone else signs in on that phone it moves to them, and
-- it is removed on sign-out.
CREATE TABLE IF NOT EXISTS push_tokens (
  token TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  environment TEXT NOT NULL DEFAULT 'production' CHECK (environment IN ('production', 'sandbox')),
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user ON push_tokens(user_id);
