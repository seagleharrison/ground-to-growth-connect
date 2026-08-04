#!/usr/bin/env bash
# One command to check everything: Go unit tests, then a live smoke test
# against a disposable temporary server (a throwaway database and port, so it
# never touches your real local dev server or its data).
#
# Usage:
#   ./scripts/test-all.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BACKEND_DIR"

export PATH="$HOME/sdk/go/bin:$PATH"

echo "======================================================================="
echo " 1/2  Go unit tests"
echo "======================================================================="
if ! go test ./...; then
  echo
  echo "Unit tests failed — stopping before the smoke test."
  exit 1
fi

echo
echo "======================================================================="
echo " 2/2  Live smoke test (temporary server, disposable database)"
echo "======================================================================="

TMP_DB_DIR=$(mktemp -d)
TEST_PORT=39001

export ENCRYPTION_KEY=$(openssl rand -hex 32)
export STAFF_INVITE_CODE=test-staff-code
export SQLITE_PATH="$TMP_DB_DIR/smoketest.db"
export PORT=$TEST_PORT
export CORS_ORIGIN="*"

go run . > /tmp/g2g-test-all-server.log 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null
  rm -rf "$TMP_DB_DIR"
}
trap cleanup EXIT

READY=false
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:$TEST_PORT/health" >/dev/null 2>&1; then
    READY=true
    break
  fi
  sleep 0.5
done

if [[ "$READY" != "true" ]]; then
  echo "Server never came up. Log:"
  cat /tmp/g2g-test-all-server.log
  exit 1
fi

"$SCRIPT_DIR/smoke-test.sh" "http://127.0.0.1:$TEST_PORT"
SMOKE_EXIT=$?

echo
echo "======================================================================="
if [[ $SMOKE_EXIT -eq 0 ]]; then
  echo " Everything passed."
else
  echo " Something in the smoke test failed — see above."
fi
echo "======================================================================="
exit $SMOKE_EXIT
