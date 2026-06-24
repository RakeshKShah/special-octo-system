#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="shortpass-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register with a too-short password
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{"email":"$TEST_EMAIL","password":"abc","role":"SELLER"}" "$BASE_URL/register")

# Then — assert password validation failure
[ "$HTTP_CODE" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
if grep -Ei 'password|short|least|min' "$RESPONSE_FILE" >/dev/null; then :; else cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:short_password_rejection'
