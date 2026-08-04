#!/usr/bin/env bash
# Walks through every API endpoint against a running server, printing what was
# expected vs what actually came back for each one.
#
# Usage:
#   ./smoke-test.sh                          # tests http://127.0.0.1:3001
#   ./smoke-test.sh https://api.groundtogrowth.org
#   STAFF_INVITE_CODE=g2g-staff ./smoke-test.sh

set -uo pipefail

BASE="${1:-http://127.0.0.1:3001}"
STAFF_CODE="${STAFF_INVITE_CODE:-g2g-staff}"
PASS=0
FAIL=0

# check DESCRIPTION EXPECTED_STATUS ACTUAL_STATUS [EXTRA_CHECK_OK]
check() {
  local desc="$1" expected="$2" actual="$3" extra_ok="${4:-true}"
  if [[ "$actual" == "$expected" && "$extra_ok" == "true" ]]; then
    printf "  PASS  %-45s expected %-5s got %-5s\n" "$desc" "$expected" "$actual"
    PASS=$((PASS + 1))
  else
    printf "  FAIL  %-45s expected %-5s got %-5s\n" "$desc" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "Testing API at $BASE"
echo "======================================================================="

# 1. Health check
resp=$(curl -s -w '\n%{http_code}' "$BASE/health")
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
ok=$(echo "$body" | jq -e '.status == "ok"' >/dev/null 2>&1 && echo true || echo false)
check "GET /health -> status ok" "200" "$status" "$ok"

# 2. Register a participant
resp=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Smoke Test Participant"}')
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
TOKEN=$(echo "$body" | jq -r '.token // empty')
ok=$([[ -n "$TOKEN" ]] && echo true || echo false)
check "POST /api/users -> returns token" "201" "$status" "$ok"

# 3. /api/me with valid token
resp=$(curl -s -w '\n%{http_code}' "$BASE/api/me" -H "Authorization: Bearer $TOKEN")
status=$(echo "$resp" | tail -1)
check "GET /api/me (valid token)" "200" "$status"

# 4. /api/me with garbage token
status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/me" -H "Authorization: Bearer garbage")
check "GET /api/me (invalid token)" "401" "$status"

# 5. Consent status before granting
resp=$(curl -s -w '\n%{http_code}' "$BASE/api/consent/status" -H "Authorization: Bearer $TOKEN")
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
ok=$(echo "$body" | jq -e '.granted == false' >/dev/null 2>&1 && echo true || echo false)
check "GET /api/consent/status (before) -> granted false" "200" "$status" "$ok"

# 6. Location blocked before consent
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/locations" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"latitude":32.0809,"longitude":-81.0912}')
check "POST /api/locations (no consent yet)" "403" "$status"

# 7. Grant consent
resp=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/consent" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"granted":true}')
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
ok=$(echo "$body" | jq -e '.record.granted == true' >/dev/null 2>&1 && echo true || echo false)
check "POST /api/consent granted:true" "200" "$status" "$ok"

# 8. Consent status after granting
resp=$(curl -s -w '\n%{http_code}' "$BASE/api/consent/status" -H "Authorization: Bearer $TOKEN")
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
ok=$(echo "$body" | jq -e '.granted == true' >/dev/null 2>&1 && echo true || echo false)
check "GET /api/consent/status (after) -> granted true" "200" "$status" "$ok"

# 9. Submit a location
resp=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/locations" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"latitude":32.0809,"longitude":-81.0912,"accuracyMeters":12.5}')
status=$(echo "$resp" | tail -1)
check "POST /api/locations (with consent)" "201" "$status"

# 10. Fetch own locations
resp=$(curl -s -w '\n%{http_code}' "$BASE/api/locations/mine" -H "Authorization: Bearer $TOKEN")
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
ok=$(echo "$body" | jq -e '.reports | length >= 1' >/dev/null 2>&1 && echo true || echo false)
check "GET /api/locations/mine -> has a report" "200" "$status" "$ok"

# 11. Non-staff blocked from staff dashboard
status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/locations/latest" -H "Authorization: Bearer $TOKEN")
check "GET /api/locations/latest (non-staff)" "403" "$status"

# 12. Staff registration with wrong invite code
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/users" \
  -H "Content-Type: application/json" \
  -d '{"name":"Fake Staff","personType":"volunteer","staffCode":"wrong-code"}')
check "POST /api/users (staff, wrong code)" "403" "$status"

# 13. Staff registration with correct invite code
resp=$(curl -s -w '\n%{http_code}' -X POST "$BASE/api/users" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Smoke Test Staff\",\"personType\":\"volunteer\",\"staffCode\":\"$STAFF_CODE\"}")
status=$(echo "$resp" | tail -1)
body=$(echo "$resp" | sed '$d')
STAFF_TOKEN=$(echo "$body" | jq -r '.token // empty')
ok=$([[ -n "$STAFF_TOKEN" ]] && echo true || echo false)
check "POST /api/users (staff, correct code)" "201" "$status" "$ok"

# 14. Staff sees the dashboard
resp=$(curl -s -w '\n%{http_code}' "$BASE/api/locations/latest" -H "Authorization: Bearer $STAFF_TOKEN")
status=$(echo "$resp" | tail -1)
check "GET /api/locations/latest (staff)" "200" "$status"

# 15. Unknown route
status=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/nope")
check "GET /api/nope (unknown route)" "404" "$status"

echo "======================================================================="
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
