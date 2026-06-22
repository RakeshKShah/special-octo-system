#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_no_products_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
STORE_NAME="New Store ${CASE_SUFFIX}"
STORE_BIO="Fresh setup"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create and activate a seller with no products and no orders.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${STORE_BIO}\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — response is 200 with empty products and orders.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.store_name' "$RESP_FILE")" = "$STORE_NAME" ]
  [ "$(jq -r '.bio' "$RESP_FILE")" = "$STORE_BIO" ]
  [ "$(jq '.products | length' "$RESP_FILE")" = "0" ]
  [ "$(jq '.orders | length' "$RESP_FILE")" = "0" ]
  [ "$(jq -r '.total_earnings_cents' "$RESP_FILE")" = "0" ]
else
  grep -F "$STORE_NAME" "$RESP_FILE" >/dev/null
  grep -F '"products":[]' "$RESP_FILE" >/dev/null
  grep -F '"orders":[]' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_no_products"

# Cleanup — remove seeded DB rows.
