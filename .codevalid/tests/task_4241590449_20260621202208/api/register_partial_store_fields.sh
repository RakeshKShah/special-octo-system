#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL_ONE="seller9-${CASE_SUFFIX}@example.com"
EMAIL_TWO="seller10-${CASE_SUFFIX}@example.com"
RESPONSE_ONE_FILE="/tmp/register_partial_store_fields_one_${CASE_SUFFIX}.json"
RESPONSE_TWO_FILE="/tmp/register_partial_store_fields_two_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email IN ('${EMAIL_ONE}','${EMAIL_TWO}'));" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email IN ('${EMAIL_ONE}','${EMAIL_TWO}');" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_ONE_FILE" "$RESPONSE_TWO_FILE"
}
trap cleanup EXIT

# Given — ensure both unique seller emails are absent
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null

# When — register one seller with storeName only and one with bio only
HTTP_STATUS_ONE="$(curl -sS -o "$RESPONSE_ONE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL_ONE}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Name Only Shop\"}")"
HTTP_STATUS_TWO="$(curl -sS -o "$RESPONSE_TWO_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL_TWO}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"bio\":\"Bio only description\"}")"

# Then — both registrations succeed with appropriate default values
[ "$HTTP_STATUS_ONE" = "201" ]
[ "$HTTP_STATUS_TWO" = "201" ]
grep -F '"storeName":"Name Only Shop"' "$RESPONSE_ONE_FILE" >/dev/null
grep -F '"bio":""' "$RESPONSE_ONE_FILE" >/dev/null
grep -F '"storeName":"My Shop"' "$RESPONSE_TWO_FILE" >/dev/null
grep -F '"bio":"Bio only description"' "$RESPONSE_TWO_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:register_partial_store_fields"

# Cleanup — remove created rows
