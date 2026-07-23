import { Router } from 'express';
import { query } from '../db.js';
import {
  generateToken,
  hashToken,
  hashUserAgent,
  encryptCoordinate,
  decryptCoordinate,
  encryptString,
  decryptString,
  snapToGrid,
} from '../crypto.js';
import { CONSENT_VERSION, DISCLOSURE_TEXT } from '../consent/disclosure.js';

const router = Router();

const PERSON_TYPES = ['homeless', 'volunteer', 'employee', 'admin'];
const STAFF_TYPES = ['volunteer', 'employee', 'admin'];
const GENDERS = ['female', 'male', 'nonbinary', 'other', 'prefer_not_to_say'];

const STAFF_INVITE_CODE = process.env.STAFF_INVITE_CODE ?? 'g2g-staff';

function isStaff(personType) {
  return STAFF_TYPES.includes(personType);
}

async function authenticate(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing bearer token' });
  }
  const tokenHash = hashToken(auth.slice(7));
  const result = await query(
    'SELECT id, person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted FROM users WHERE token_hash = $1',
    [tokenHash]
  );
  if (result.rows.length === 0) {
    return res.status(401).json({ error: 'Invalid token' });
  }
  req.user = result.rows[0];
  next();
}

function requireStaff(req, res, next) {
  if (!isStaff(req.user.person_type)) {
    return res.status(403).json({ error: 'Staff access required' });
  }
  next();
}

async function requireConsent(req, res, next) {
  const result = await query(
    'SELECT granted FROM user_consent_status WHERE user_id = $1',
    [req.user.id]
  );
  if (result.rows.length === 0 || !result.rows[0].granted) {
    return res.status(403).json({ error: 'Location tracking consent not granted' });
  }
  next();
}

function profileFromRow(row) {
  return {
    id: row.id,
    personType: row.person_type,
    name: decryptString(row.name_encrypted),
    email: row.email_encrypted ? decryptString(row.email_encrypted) : null,
    gender: row.gender_encrypted ? decryptString(row.gender_encrypted) : null,
    phone: row.phone_encrypted ? decryptString(row.phone_encrypted) : null,
    isStaff: isStaff(row.person_type),
  };
}

// --- Users ---

router.post('/users', async (req, res) => {
  const { name, email, gender, phone, personType, staffCode } = req.body;

  if (!name?.trim()) {
    return res.status(400).json({ error: 'name is required' });
  }
  const type = personType ?? 'homeless';
  if (!PERSON_TYPES.includes(type)) {
    return res.status(400).json({ error: `personType must be one of: ${PERSON_TYPES.join(', ')}` });
  }
  if (gender && !GENDERS.includes(gender)) {
    return res.status(400).json({ error: `gender must be one of: ${GENDERS.join(', ')}` });
  }
  // Staff roles require an invite code so participants' locations stay protected.
  if (isStaff(type) && staffCode !== STAFF_INVITE_CODE) {
    return res.status(403).json({ error: 'A valid staff invite code is required for staff accounts.' });
  }

  const token = generateToken();
  const tokenHash = hashToken(token);

  const result = await query(
    `INSERT INTO users (person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted, token_hash)
     VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING id, person_type, name_encrypted, email_encrypted, gender_encrypted, phone_encrypted, created_at`,
    [
      type,
      encryptString(name.trim().slice(0, 200)),
      email?.trim() ? encryptString(email.trim().slice(0, 200)) : null,
      gender ? encryptString(gender) : null,
      phone?.trim() ? encryptString(phone.trim().slice(0, 40)) : null,
      tokenHash,
    ]
  );

  res.status(201).json({
    user: profileFromRow(result.rows[0]),
    token,
    message: 'Store this token securely. It cannot be recovered.',
  });
});

router.get('/me', authenticate, (req, res) => {
  res.json({ user: profileFromRow(req.user) });
});

router.delete('/account', authenticate, async (req, res) => {
  // Cascades to consent_records and location_reports.
  await query('DELETE FROM users WHERE id = $1', [req.user.id]);
  res.json({ deleted: true });
});

// --- Consent ---

router.get('/consent/disclosure', (_req, res) => {
  res.json({ version: CONSENT_VERSION, text: DISCLOSURE_TEXT });
});

router.get('/consent/status', authenticate, async (req, res) => {
  const result = await query(
    `SELECT granted, consent_version, granted_at, revoked_at, last_recorded_at
     FROM user_consent_status WHERE user_id = $1`,
    [req.user.id]
  );
  if (result.rows.length === 0) {
    return res.json({ granted: false, version: CONSENT_VERSION });
  }
  const row = result.rows[0];
  res.json({ ...row, granted: Boolean(row.granted) });
});

router.get('/consent/history', authenticate, async (req, res) => {
  const result = await query(
    `SELECT id, consent_version, granted, granted_at, revoked_at, created_at
     FROM consent_records WHERE user_id = $1 ORDER BY created_at DESC LIMIT 50`,
    [req.user.id]
  );
  const records = result.rows.map((r) => ({ ...r, granted: Boolean(r.granted) }));
  res.json({ records });
});

router.post('/consent', authenticate, async (req, res) => {
  const { granted } = req.body;
  if (typeof granted !== 'boolean') {
    return res.status(400).json({ error: 'granted must be a boolean' });
  }

  const now = new Date();
  const uaHash = hashUserAgent(req.headers['user-agent']);

  const result = await query(
    `INSERT INTO consent_records
       (user_id, consent_version, disclosure_text, granted, granted_at, revoked_at, user_agent_hash)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id, consent_version, granted, granted_at, revoked_at, created_at`,
    [
      req.user.id,
      CONSENT_VERSION,
      DISCLOSURE_TEXT,
      granted,
      granted ? now : null,
      granted ? null : now,
      uaHash,
    ]
  );

  const record = result.rows[0];
  res.json({ record: { ...record, granted: Boolean(record.granted) } });
});

// --- Locations ---

router.post('/locations', authenticate, requireConsent, async (req, res) => {
  const { latitude, longitude, accuracyMeters, reportedAt } = req.body;

  if (typeof latitude !== 'number' || typeof longitude !== 'number') {
    return res.status(400).json({ error: 'latitude and longitude are required numbers' });
  }
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return res.status(400).json({ error: 'Invalid coordinates' });
  }

  // Snap to a fixed ~200m privacy grid, then encrypt.
  const [gridLat, gridLng] = snapToGrid(latitude, longitude);
  const latEnc = encryptCoordinate(gridLat);
  const lngEnc = encryptCoordinate(gridLng);
  const reported = reportedAt ? new Date(reportedAt) : new Date();

  const result = await query(
    `INSERT INTO location_reports
       (user_id, latitude_encrypted, longitude_encrypted, accuracy_meters, reported_at)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, reported_at, created_at`,
    [req.user.id, latEnc, lngEnc, accuracyMeters ?? null, reported]
  );

  res.status(201).json({ report: result.rows[0] });
});

// Staff-only: latest location per participant (homeless) with active consent.
router.get('/locations/latest', authenticate, requireStaff, async (_req, res) => {
  const result = await query(
    `SELECT user_id, name_encrypted, person_type, latitude_encrypted, longitude_encrypted,
            accuracy_meters, reported_at
     FROM (
       SELECT
         u.id AS user_id,
         u.name_encrypted,
         u.person_type,
         lr.latitude_encrypted,
         lr.longitude_encrypted,
         lr.accuracy_meters,
         lr.reported_at,
         ROW_NUMBER() OVER (
           PARTITION BY lr.user_id ORDER BY lr.reported_at DESC, lr.id DESC
         ) AS rn
       FROM location_reports lr
       JOIN users u ON u.id = lr.user_id
       JOIN user_consent_status cs ON cs.user_id = u.id AND cs.granted = 1
       WHERE u.person_type = 'homeless'
     )
     WHERE rn = 1`
  );

  const locations = result.rows.map((row) => ({
    userId: row.user_id,
    name: decryptString(row.name_encrypted),
    personType: row.person_type,
    latitude: decryptCoordinate(row.latitude_encrypted),
    longitude: decryptCoordinate(row.longitude_encrypted),
    accuracyMeters: row.accuracy_meters,
    reportedAt: row.reported_at,
  }));

  res.json({ locations });
});

router.get('/locations/mine', authenticate, async (req, res) => {
  const result = await query(
    `SELECT latitude_encrypted, longitude_encrypted, accuracy_meters, reported_at
     FROM location_reports
     WHERE user_id = $1
     ORDER BY reported_at DESC
     LIMIT 100`,
    [req.user.id]
  );

  const reports = result.rows.map((row) => ({
    latitude: decryptCoordinate(row.latitude_encrypted),
    longitude: decryptCoordinate(row.longitude_encrypted),
    accuracyMeters: row.accuracy_meters,
    reportedAt: row.reported_at,
  }));

  res.json({ reports });
});

export default router;
