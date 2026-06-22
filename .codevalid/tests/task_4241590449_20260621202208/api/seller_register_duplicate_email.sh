#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="existing-${CASE_SUFFIX}@example.com"
FIRST_RESPONSE_FILE="/tmp/seller_register_duplicate_email_first_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_register_duplicate_email_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$FIRST_RESPONSE_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — create an existing registered seller with the target email
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
FIRST_STATUS="$(curl -sS -o "$FIRST_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Existing Shop\"}")"
[ "$FIRST_STATUS" = "201" ]

# When — try registering again with the same email
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"New Shop\"}")"

# Then — response is 400 with duplicate email error
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":"Email already registered"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_duplicate_email"

# Cleanup — remove created rows
