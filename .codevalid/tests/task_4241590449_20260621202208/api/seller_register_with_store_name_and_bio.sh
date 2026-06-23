#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller2-${CASE_SUFFIX}@example.com"
STORE_NAME="Eco Friendly Goods ${CASE_SUFFIX}"
BIO="Sustainable products for a better tomorrow ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_register_with_store_name_and_bio_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure database reachability and absence of prior rows for this unique seller email.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true

# When — register a seller with custom storeName and bio.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"AnotherPass456!\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}")"

# Then — response is 201 with persisted custom profile values and PENDING status.
[ "$HTTP_STATUS" = "201" ]
grep -F '"email":"'"${SELLER_EMAIL}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"storeName":"'"${STORE_NAME}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"'"${BIO}"'"' "$RESPONSE_FILE" >/dev/null
grep -F '"token":"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_with_store_name_and_bio"

# Cleanup — remove created user and seller profile. Handled by trap.
