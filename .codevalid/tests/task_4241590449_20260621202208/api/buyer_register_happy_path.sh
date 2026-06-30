#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="buyer-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register a buyer
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"BuyerPass123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")

# Then — assert buyer becomes ACTIVE and has no seller profile
[ "$HTTP_CODE" = "201" ]
grep -F '"token"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"'"$TEST_EMAIL"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"role":"BUYER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
if grep -F '"sellerProfile":null' "$RESPONSE_FILE" >/dev/null; then :; elif grep -F '"sellerProfile"' "$RESPONSE_FILE" >/dev/null; then cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:buyer_register_happy_path'
