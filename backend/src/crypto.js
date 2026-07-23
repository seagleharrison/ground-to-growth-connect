import crypto from 'crypto';

const ALGORITHM = 'aes-256-gcm';
const IV_LENGTH = 12;

/** Fixed privacy grid size, in meters. Coordinates are snapped to this grid. */
export const GRID_METERS = 200;
const METERS_PER_DEG_LAT = 111_320;

function getKey() {
  const hex = process.env.ENCRYPTION_KEY;
  if (!hex || hex.length !== 64) {
    throw new Error(
      'ENCRYPTION_KEY must be a 64-character hex string (32 bytes). ' +
        'Generate with: openssl rand -hex 32'
    );
  }
  return Buffer.from(hex, 'hex');
}

/** Encrypt a string to an [iv | tag | ciphertext] Buffer (for BLOB storage). */
export function encryptString(value) {
  if (value == null) return null;
  const iv = crypto.randomBytes(IV_LENGTH);
  const cipher = crypto.createCipheriv(ALGORITHM, getKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(String(value), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, encrypted]);
}

/** Decrypt a Buffer produced by encryptString back to a string. */
export function decryptString(blob) {
  if (blob == null) return null;
  const buf = Buffer.from(blob);
  const iv = buf.subarray(0, IV_LENGTH);
  const tag = buf.subarray(IV_LENGTH, IV_LENGTH + 16);
  const encrypted = buf.subarray(IV_LENGTH + 16);
  const decipher = crypto.createDecipheriv(ALGORITHM, getKey(), iv);
  decipher.setAuthTag(tag);
  const decrypted = Buffer.concat([
    decipher.update(encrypted),
    decipher.final(),
  ]);
  return decrypted.toString('utf8');
}

export function encryptCoordinate(value) {
  return encryptString(String(value));
}

export function decryptCoordinate(blob) {
  return parseFloat(decryptString(blob));
}

/**
 * Snap a coordinate pair to a fixed ~200m grid before storage.
 * Longitude cell size is adjusted by latitude so cells stay ~200m wide.
 * Returns [snappedLat, snappedLng].
 */
export function snapToGrid(lat, lng) {
  const latCell = GRID_METERS / METERS_PER_DEG_LAT;
  const snappedLat = Math.round(lat / latCell) * latCell;

  const cos = Math.cos((lat * Math.PI) / 180);
  const lngCell = GRID_METERS / (METERS_PER_DEG_LAT * Math.max(Math.abs(cos), 1e-6));
  const snappedLng = Math.round(lng / lngCell) * lngCell;

  return [
    Math.round(snappedLat * 1e6) / 1e6,
    Math.round(snappedLng * 1e6) / 1e6,
  ];
}

export function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

export function hashUserAgent(userAgent) {
  if (!userAgent) return null;
  return crypto.createHash('sha256').update(userAgent).digest('hex');
}

export function generateToken() {
  return crypto.randomBytes(32).toString('hex');
}
