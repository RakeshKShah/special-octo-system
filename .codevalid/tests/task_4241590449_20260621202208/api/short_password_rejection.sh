#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/short_password_rejection_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — stateless validation scenario
:

# When — submit a too-short password
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data '{"email":"shortpass@example.com","password":"abc","role":"SELLER"}')"

# Then — assert validation failure response
[ "$HTTP_STATUS" = "400" ]
jq -e '.error | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:short_password_rejection"
