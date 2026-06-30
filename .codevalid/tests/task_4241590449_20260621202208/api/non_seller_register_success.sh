#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer1-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/non_seller_register_success_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${BUYER_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${BUYER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure database reachability and absence of prior rows for this unique buyer email.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${BUYER_EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${BUYER_EMAIL}';" >/dev/null 2>&1 || true

# When — register a non-seller BUYER account.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"BuyerPass321!\",\"role\":\"BUYER\"}")"

# Then — response is 201 with BUYER role, ACTIVE status, null sellerProfile, and token.
[ "$HTTP_STATUS" = "201" ]
grep -F '"email":"'"${BUYER_EMAIL}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"role":"BUYER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"sellerProfile":null' "$RESPONSE_FILE" >/dev/null
grep -F '"token":"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_register_success"

# Cleanup — remove created user. Handled by trap.
