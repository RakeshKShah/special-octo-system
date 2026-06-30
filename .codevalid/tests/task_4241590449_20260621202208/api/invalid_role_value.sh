#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="unknown-role-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register with an unsupported role value
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"ValidPass123!\",\"role\":\"ADMIN\"}" "$BASE_URL/auth/register")

# Then — assert enum validation failure
[ "$HTTP_CODE" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
if grep -Ei 'role|invalid|enum' "$RESPONSE_FILE" >/dev/null; then :; else cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:invalid_role_value'
