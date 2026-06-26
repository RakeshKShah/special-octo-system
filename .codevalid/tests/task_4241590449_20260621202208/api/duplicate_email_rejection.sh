#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="dup-${CASE_SUFFIX}@example.com"
SETUP_RESPONSE_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$SETUP_RESPONSE_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — create an existing user with the same email through the public API
SETUP_HTTP_CODE=$(curl -sS -o "$SETUP_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"BuyerPass123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")
[ "$SETUP_HTTP_CODE" = "201" ]

# When — attempt to register another account with the duplicate email
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"AnotherPass1!\",\"role\":\"SELLER\",\"storeName\":\"Duplicate Shop\",\"bio\":\"duplicate attempt\"}" "$BASE_URL/auth/register")

# Then — assert duplicate email rejection
[ "$HTTP_CODE" = "400" ]
grep -F '"error":"Email already registered"' "$RESPONSE_FILE" >/dev/null

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:duplicate_email_rejection'
