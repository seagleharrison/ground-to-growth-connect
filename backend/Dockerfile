# --- Build stage: install deps and compile better-sqlite3 native addon ---
FROM node:22-bookworm-slim AS build
WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY . .

# --- Runtime stage ---
FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production

COPY --from=build /app /app

# Persistent data directory (mounted volume in production)
RUN mkdir -p /data
ENV SQLITE_PATH=/data/locvault.db

EXPOSE 3001

# Run idempotent migration, then start the API.
CMD ["sh", "-c", "node src/migrate.js && node src/index.js"]
