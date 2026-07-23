# LocVault v0.1

Privacy-first location tracking with a **SQL backend** (PostgreSQL), encrypted storage, and auditable consent records.

## Features

- **15-minute location reports** — client sends location at most once every 15 minutes
- **Privacy coarsening** — coordinates rounded to ~100m before encryption
- **Encryption at rest** — AES-256-GCM for latitude/longitude in PostgreSQL
- **Consent management** — full disclosure text, grant/revoke, immutable audit log in SQL
- **Simple map UI** — view latest locations for consented users

## Architecture

```
iOS app (SwiftUI)  ─┐
web app (React)    ─┼→  backend (Express)  →  PostgreSQL
                    ↓
              AES-256-GCM encryption
```

## Quick start

### 1. Start PostgreSQL

```bash
docker compose up -d
```

### 2. Configure backend

```bash
cd backend
cp .env.example .env
# Generate a key: openssl rand -hex 32
# Paste into ENCRYPTION_KEY in .env
npm install
npm run migrate
npm run dev
```

### 3. Start frontend

```bash
cd frontend
npm install
npm run dev
```

Open http://localhost:5173

### 4. iOS app

```bash
open "ios/Ground to Growth Connect.xcodeproj"
```

Set your Development Team in Xcode, run on simulator or device. See [ios/README.md](ios/README.md) for API URL setup (simulator uses `http://127.0.0.1:3001`; physical devices need your Mac's LAN IP).

## API

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/users` | Register (returns one-time token) |
| GET | `/api/consent/disclosure` | Current disclosure text |
| GET | `/api/consent/status` | Current consent status |
| POST | `/api/consent` | Grant or revoke consent |
| GET | `/api/consent/history` | Consent audit log |
| POST | `/api/locations` | Submit location (requires consent) |
| GET | `/api/locations/latest` | Latest location per consented user |

## Privacy notes

- **Web:** tokens in sessionStorage only (cleared when tab closes)
- **iOS:** tokens in Keychain (`WhenUnlockedThisDeviceOnly`)
- User-agent is stored as a **SHA-256 hash** with consent records, not raw
- Location data is **never stored in plaintext** in the database
- Revoking consent immediately stops the client-side reporting interval
- Use **HTTPS** and rotate `ENCRYPTION_KEY` carefully in production

## SQL schema

See `backend/sql/001_init.sql` for tables: `users`, `consent_records`, `location_reports`, and the `user_consent_status` view.
