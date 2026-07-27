# --- Build stage: compile a static Go binary ---
FROM golang:1.25-bookworm AS build
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download
COPY . .

# modernc.org/sqlite is pure Go (no CGO), so this cross-builds cleanly with a
# fully static binary and no native toolchain needed at runtime.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/server .

# --- Runtime stage ---
FROM alpine:3.20
RUN apk add --no-cache curl \
  && addgroup -S app && adduser -S -G app app
WORKDIR /app

COPY --from=build /out/server ./server

# Persistent data directory (mounted volume in production).
RUN mkdir -p /data && chown -R app:app /data /app
ENV SQLITE_PATH=/data/locvault.db
USER app

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:3001/health || exit 1

# The migration is idempotent and runs automatically on startup, before the
# server begins listening.
CMD ["./server"]
