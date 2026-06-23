#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller1-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_register_success_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure the database is reachable and no conflicting user exists for this unique email.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true

# When — register a seller with valid required fields.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\"}")"

# Then — response is 201 with SELLER role, PENDING status, default seller profile values, and token.
[ "$HTTP_STATUS" = "201" ]
grep -F '"email":"'"${SELLER_EMAIL}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"role":"SELLER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"storeName":"My Shop"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":""' "$RESPONSE_FILE" >/dev/null
grep -F '"token":"' "$RESPONSE_FILE" >/dev/null
grep -F '"sellerProfile":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_success"

# Cleanup — remove created user and seller profile. Handled by trap.
