# --- Build stage: install deps and compile the better-sqlite3 native addon ---
FROM node:22-bookworm-slim AS build
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
# Reproducible install from the lockfile; falls back to install if no lockfile.
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi

COPY . .

# --- Runtime stage ---
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production

# curl is used by the container HEALTHCHECK.
RUN apt-get update \
  && apt-get install -y --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /app /app

# Persistent data directory (mounted volume in production). Owned by the
# unprivileged `node` user that the base image already provides.
RUN mkdir -p /data && chown -R node:node /data /app
ENV SQLITE_PATH=/data/locvault.db
USER node

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3001/health || exit 1

# Run the idempotent migration, then start the API.
CMD ["sh", "-c", "node src/migrate.js && node src/index.js"]
