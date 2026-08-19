# Deploying the Ground to Growth Connect API (VPS + containers)

This runs the Go + SQLite backend as a Docker container on your own VPS, with a
persistent volume for the database and optional automatic HTTPS via Caddy.

Architecture:

```
            (HTTPS 443)                 (internal network)
Internet ──▶  Caddy container  ──────▶  api container (Node/Express :3001)
             auto Let's Encrypt         │
                                        ▼
                               g2g_data volume  →  /data/locvault.db  (encrypted PII + coords)
```

---

## 1. Prerequisites on the VPS

- A Linux VPS (Ubuntu/Debian assumed below) with SSH access.
- Docker Engine + the Compose plugin. Install if needed:

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"   # then log out/in so `docker` works without sudo
docker --version && docker compose version
```

- **For HTTPS:** a domain/subdomain (e.g. `api.groundtogrowth.org`) with a DNS
  **A record pointing at the VPS's public IP**, and ports **80 + 443** open in the firewall.

---

## 2. Get the code

```bash
git clone https://github.com/seagleharrison/ground-to-growth-connect.git
cd ground-to-growth-connect
```

---

## 3. Configure secrets

```bash
cp .env.example .env
# Generate a strong encryption key and put it in .env:
openssl rand -hex 32
```

Edit `.env` and set at minimum:

- `ENCRYPTION_KEY` — the 64-char hex value you just generated.
  **Back this up.** If it changes, previously stored data can't be decrypted.
- `STAFF_INVITE_CODE` — the code staff enter to register privileged accounts.
- For HTTPS: `DOMAIN` and `TLS_EMAIL`.
- `CORS_ORIGIN` — set to your web app's URL if you deploy the frontend (or `*`).
- `B2_ENDPOINT` / `B2_REGION` / `B2_BUCKET` / `B2_KEY_ID` / `B2_APPLICATION_KEY` —
  where uploaded documents are stored (Backblaze B2). Optional: if left unset,
  documents are stored encrypted inside the container's own volume instead —
  works fine, just without B2's offsite durability. To set up a bucket:
  1. Create a Backblaze account and a new **private** bucket.
  2. Open the bucket, copy its **Endpoint** — `B2_REGION` is the middle segment
     (`https://s3.«B2_REGION».backblazeb2.com`).
  3. **App Keys → Add a New Application Key**, scoped to just that bucket.
     Copy `keyID` → `B2_KEY_ID` and `applicationKey` → `B2_APPLICATION_KEY`
     (the application key is shown once — save it immediately).
  Documents are encrypted (AES-256-GCM) before they're ever uploaded, so B2
  itself only ever stores unreadable ciphertext.

`.env` is git-ignored; never commit it.

---

## 4. Run it

### Option A — Automatic HTTPS (recommended for real devices)

Requires `DOMAIN` + `TLS_EMAIL` set and DNS pointed at the VPS.

```bash
docker compose --profile tls up -d --build
```

Caddy obtains a certificate automatically. Your API is then live at:

```
https://YOUR_DOMAIN/health   ->  {"status":"ok","version":"0.1.0"}
```

### Option B — Direct HTTP (quick testing only)

Expose the API port directly (iOS will need an ATS exception for plain HTTP, so
use this only for testing):

```bash
# In .env set:  API_BIND=0.0.0.0
docker compose up -d --build
curl http://YOUR_VPS_IP:3001/health
```

### Option C — Behind your existing reverse proxy

Leave `API_BIND=127.0.0.1` (default) and point your nginx/Traefik upstream at
`127.0.0.1:3001`. Start with `docker compose up -d --build` (no `tls` profile).

---

## 5. Point the app at the API

In the iOS app: **Settings → API base URL** →

```
https://YOUR_DOMAIN
```

Over HTTPS it works on cellular and any Wi-Fi.

---

## 6. Operating it

**Logs**
```bash
docker compose logs -f api
```

**Update after code changes**
```bash
git pull
docker compose --profile tls up -d --build   # omit --profile tls if not using Caddy
```

**Back up the database**
```bash
docker compose exec api sh -c "cat /data/locvault.db" > backup-$(date +%F).db
```

**Restore**
```bash
docker compose down
docker run --rm -v ground-to-growth-connect_g2g_data:/data -v "$PWD":/backup alpine \
  sh -c "cp /backup/backup-YYYY-MM-DD.db /data/locvault.db"
docker compose --profile tls up -d
```

---

## Guardrails

- **Single instance only.** SQLite is one file on one volume — do not run multiple
  API replicas. If you outgrow it, migrate to Postgres and update `backend/src/db.js`.
- **Protect `ENCRYPTION_KEY` and `.env`.** Store the key in a password manager.
- **Firewall:** only expose 80/443 (Caddy) publicly; keep 3001 bound to localhost.
- **The migration is idempotent** and runs automatically on container start.

---

## Alternative: Fly.io

A `backend/fly.toml` is also included if you'd rather use Fly's managed volumes
instead of a VPS. See the file for the app/volume config.
