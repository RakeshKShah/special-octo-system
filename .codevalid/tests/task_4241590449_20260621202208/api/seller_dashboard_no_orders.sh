#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_no_orders_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
STORE_NAME="Quiet Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "Product" WHERE id = 'prod-none-${CASE_SUFFIX}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create and activate seller with one product and no order items.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Premium goods\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
VALUES ('prod-none-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Premium Item', 'Premium desc', 'HOME', 10000, 3, '["https://example.test/premium.jpg"]', 'ACTIVE', true, NOW(), NOW());
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — response is 200 with one product, no orders, and zero earnings.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq '.products | length' "$RESP_FILE")" = "1" ]
  [ "$(jq -r '.products[0].title' "$RESP_FILE")" = "Premium Item" ]
  [ "$(jq '.orders | length' "$RESP_FILE")" = "0" ]
  [ "$(jq -r '.total_earnings_cents' "$RESP_FILE")" = "0" ]
else
  grep -F 'Premium Item' "$RESP_FILE" >/dev/null
  grep -F '"orders":[]' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_no_orders"

# Cleanup — remove seeded DB rows.
