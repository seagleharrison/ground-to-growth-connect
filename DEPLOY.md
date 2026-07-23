# Deploying the Ground to Growth Connect backend

This deploys the Node + SQLite backend to **Fly.io** with a persistent volume, so your
iPhone can reach it from anywhere over HTTPS (not just on your home Wi-Fi).

> Why Fly.io? SQLite is a single file, so it needs a persistent disk that stays attached
> to one machine. Fly volumes handle that simply. (Platforms with ephemeral disks like a
> basic Render/Heroku dyno would lose the database on every restart.)

## Prerequisites

- A Fly.io account (free to create): https://fly.io
- The Fly CLI (`flyctl`)

Install the CLI:

```bash
# macOS (Homebrew)
brew install flyctl

# or the official installer
curl -L https://fly.io/install.sh | sh
```

## One-time setup

```bash
cd backend

# 1. Sign in (opens browser)
fly auth login

# 2. Create the app from the existing fly.toml WITHOUT deploying yet.
#    If the name "ground-to-growth-connect" is taken, pass a different --name
#    and update the `app = ...` line in fly.toml to match.
fly launch --copy-config --no-deploy

# 3. Create the persistent volume for the SQLite database (1 GB).
fly volumes create locvault_data --size 1 --region iad

# 4. Set the encryption key as a SECRET (never commit this).
#    Use a brand-new key for production and keep it safe — if it ever changes,
#    previously stored location data can no longer be decrypted.
fly secrets set ENCRYPTION_KEY=$(openssl rand -hex 32)
```

## Deploy

```bash
cd backend
fly deploy
```

When it finishes, your API is live at:

```
https://ground-to-growth-connect.fly.dev
```

(Substitute your app name if you changed it. Check with `fly info` or `fly open`.)

Verify:

```bash
curl https://ground-to-growth-connect.fly.dev/health
# -> {"status":"ok","version":"0.1.0"}
```

## Point the app at the cloud backend

In the iOS app: **Settings → API base URL** →

```
https://ground-to-growth-connect.fly.dev
```

Because it's HTTPS, it works over cellular and any Wi-Fi — the Mac no longer needs to be running.

## Pushing backend updates

Every time you change backend code:

```bash
cd backend
fly deploy
```

## Notes & guardrails

- **Keep it to ONE machine.** SQLite lives on a single volume; do not run `fly scale count 2+`.
- **Back up the database** periodically: `fly ssh console -C "cat /data/locvault.db" > backup.db` (or use `fly ssh sftp`).
- **CORS**: the web frontend's allowed origin is still `http://localhost:5173`. If you deploy
  the web app too, set `CORS_ORIGIN` (e.g. `fly secrets set CORS_ORIGIN=https://yourweb.app`).
- **Cost**: a single `shared-cpu-1x` / 256 MB machine + 1 GB volume is very cheap and often
  within Fly's low-cost tier, but check current Fly pricing.
- **Scaling later**: if you outgrow SQLite, switch to Fly Postgres and update `backend/src/db.js`.
