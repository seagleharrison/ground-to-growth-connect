import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const dbPath =
  process.env.SQLITE_PATH ?? path.join(__dirname, '../locvault.db');

export const db = new Database(dbPath);
db.pragma('journal_mode = WAL');
db.pragma('foreign_keys = ON');

/**
 * Minimal pg-style query shim over better-sqlite3.
 * - Converts $1, $2, ... placeholders to positional `?`.
 * - Normalizes JS params (booleans -> 0/1, Date -> ISO string, undefined -> null).
 * - Returns { rows } like node-postgres.
 */
export function query(text, params = []) {
  const sql = text.replace(/\$(\d+)/g, '?');

  const normalized = (params ?? []).map((p) => {
    if (p === undefined) return null;
    if (typeof p === 'boolean') return p ? 1 : 0;
    if (p instanceof Date) return p.toISOString();
    return p;
  });

  const stmt = db.prepare(sql);
  const returnsRows = /^\s*(select|with)\b/i.test(sql) || /\breturning\b/i.test(sql);

  if (returnsRows) {
    return { rows: stmt.all(...normalized) };
  }

  const info = stmt.run(...normalized);
  return { rows: [], rowCount: info.changes };
}

export function migrate() {
  const sqlPath = path.join(__dirname, '../sql/001_init.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');
  db.exec(sql);
  console.log(`Migration complete. Database: ${dbPath}`);
}
