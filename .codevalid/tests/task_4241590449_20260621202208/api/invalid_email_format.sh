#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — malformed email input will be used

# When — register with an invalid email format
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"invalid-email\",\"password\":\"ValidPass123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")

# Then — assert schema validation error
[ "$HTTP_CODE" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
if grep -Ei 'email|invalid' "$RESPONSE_FILE" >/dev/null; then :; else cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — stateless request only

echo 'CODEVALID_TEST_ASSERTION_OK:invalid_email_format'
