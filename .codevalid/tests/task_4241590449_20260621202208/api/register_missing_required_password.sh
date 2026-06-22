#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/register_missing_required_password_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — prepare a request omitting required password
: "ready"

# When — POST /register without password
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data '{"email":"seller4@example.com","role":"SELLER","storeName":"Test Shop"}')"

# Then — response is 400 with an error field
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:register_missing_required_password"

# Cleanup — no side effects expected
