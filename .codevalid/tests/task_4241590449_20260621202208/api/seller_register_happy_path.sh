#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="seller-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register a seller with explicit store profile fields
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{"email":"$TEST_EMAIL","password":"SellerPass123!","role":"SELLER","storeName":"Garden Goods","bio":"Fresh from the garden"}" "$BASE_URL/register")

# Then — assert seller registration response
[ "$HTTP_CODE" = "201" ]
grep -F '"token"' "$RESPONSE_FILE" >/dev/null
grep -F '"email":"'"$TEST_EMAIL"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"role":"SELLER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"storeName":"Garden Goods"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Fresh from the garden"' "$RESPONSE_FILE" >/dev/null

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:seller_register_happy_path'
