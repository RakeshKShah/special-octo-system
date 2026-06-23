#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TOXIPROXY_URL="${TOXIPROXY_URL:-http://toxiproxy:8474}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="dbfail-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/registration_database_failure_${CASE_SUFFIX}.json"
TOXIC_NAME="db_timeout_${CASE_SUFFIX}"

cleanup() {
  curl -sS -X DELETE "$TOXIPROXY_URL/proxies/postgres/toxics/$TOXIC_NAME" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — inject a toxiproxy timeout toxic on the postgres proxy to simulate DB failure.
curl -sS "$TOXIPROXY_URL/version" >/dev/null
curl -sS -X POST "$TOXIPROXY_URL/proxies/postgres/toxics" \
  -H 'Content-Type: application/json' \
  --data "{\"name\":\"${TOXIC_NAME}\",\"type\":\"timeout\",\"stream\":\"downstream\",\"attributes\":{\"timeout\":1000}}" >/dev/null

# When — attempt seller registration while postgres is unavailable through toxiproxy.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"DBFailPass!\",\"role\":\"SELLER\"}" || true)"

# Then — response is generic 500 without leaking internal details.
[ "$HTTP_STATUS" = "500" ]
grep -F '"error":"Registration failed"' "$RESPONSE_FILE" >/dev/null
if grep -E 'stack|Prisma|ECONN|timeout|Error:' "$RESPONSE_FILE" >/dev/null 2>&1; then
  exit 1
fi

echo "CODEVALID_TEST_ASSERTION_OK:registration_database_failure"

# Cleanup — remove toxiproxy toxic. Handled by trap.
