#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/invalid_email_format_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — stateless validation scenario
:

# When — submit malformed email
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data '{"email":"invalid-email","password":"ValidPass123!","role":"BUYER"}')"

# Then — assert validation failure response
[ "$HTTP_STATUS" = "400" ]
jq -e '.error | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:invalid_email_format"
