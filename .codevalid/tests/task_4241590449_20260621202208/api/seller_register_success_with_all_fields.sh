#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller1-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_register_success_with_all_fields_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure no user exists for this unique seller email
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true

# When — register a seller with storeName and bio
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Artisan Goods\",\"bio\":\"Handmade crafts and artisanal products\"}")"

# Then — response is 201 with token, seller info, pending status, and hashed password in DB
[ "$HTTP_STATUS" = "201" ]
grep -F '"token":' "$RESPONSE_FILE" >/dev/null
grep -F "\"email\":\"${EMAIL}\"" "$RESPONSE_FILE" >/dev/null
grep -F '"role":"SELLER"' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
grep -F '"storeName":"Artisan Goods"' "$RESPONSE_FILE" >/dev/null
grep -F '"bio":"Handmade crafts and artisanal products"' "$RESPONSE_FILE" >/dev/null
PASSWORD_HASH="$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "SELECT \"passwordHash\" FROM \"User\" WHERE email = '${EMAIL}' LIMIT 1;")"
[ -n "$PASSWORD_HASH" ]
[ "$PASSWORD_HASH" != "SecurePass123!" ]
printf '%s' "$PASSWORD_HASH" | grep -E '^\$2[aby]\$' >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_success_with_all_fields"

# Cleanup — remove created seller profile and user rows
