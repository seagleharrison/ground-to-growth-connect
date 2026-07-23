import 'dotenv/config';
import { migrate } from './db.js';

try {
  migrate();
  process.exit(0);
} catch (err) {
  console.error('Migration failed:', err);
  process.exit(1);
}
