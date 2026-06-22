#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="newseller-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_register_pending_status_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure unique seller email is absent
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null

# When — register a seller
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Pending Shop\"}")"

# Then — response is 201 and seller status is PENDING in response and DB
[ "$HTTP_STATUS" = "201" ]
grep -F '"status":"PENDING"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "SELECT status FROM \"User\" WHERE email = '${EMAIL}' LIMIT 1;")"
[ "$DB_STATUS" = "PENDING" ]

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_pending_status"

# Cleanup — remove created rows
