#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_order_limit_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
BUYER_EMAIL="buyer_${CASE_SUFFIX}@example.com"
STORE_NAME="Busy Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id LIKE 'item-limit-%-${CASE_SUFFIX}';
DELETE FROM "Order" WHERE id LIKE 'order-limit-%-${CASE_SUFFIX}';
DELETE FROM "Product" WHERE id = 'prod-limit-${CASE_SUFFIX}';
DELETE FROM "User" WHERE email = '${BUYER_EMAIL}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create active seller with 75 order items across descending timestamps.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"High volume\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "User" (id, email, "passwordHash", role, status, "createdAt", "updatedAt")
VALUES ('buyer-${CASE_SUFFIX}', '${BUYER_EMAIL}', 'seeded-hash', 'BUYER', 'ACTIVE', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
VALUES ('prod-limit-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Busy Product', 'Load test product', 'HOME', 1000, 100, '["https://example.test/busy.jpg"]', 'ACTIVE', true, NOW(), NOW());
INSERT INTO "Order" (id, "buyerId", status, "createdAt", "updatedAt")
SELECT 'order-limit-' || g::text || '-${CASE_SUFFIX}', 'buyer-${CASE_SUFFIX}', 'PAID', NOW() - ((75 - g) || ' minutes')::interval, NOW() - ((75 - g) || ' minutes')::interval
FROM generate_series(1,75) g;
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents", "createdAt", "updatedAt")
SELECT 'item-limit-' || g::text || '-${CASE_SUFFIX}', 'order-limit-' || g::text || '-${CASE_SUFFIX}', 'prod-limit-${CASE_SUFFIX}', 1, 100, NOW() - ((75 - g) || ' minutes')::interval, NOW() - ((75 - g) || ' minutes')::interval
FROM generate_series(1,75) g;
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — only 50 most recent order items are returned in descending order.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq '.orders | length' "$RESP_FILE")" = "50" ]
  [ "$(jq -r '.orders[0].order_id' "$RESP_FILE")" = "order-limit-75-${CASE_SUFFIX}" ]
  [ "$(jq -r '.orders[49].order_id' "$RESP_FILE")" = "order-limit-26-${CASE_SUFFIX}" ]
else
  count="$(grep -o 'order-limit-' "$RESP_FILE" | wc -l | tr -d ' ')"
  [ "$count" -ge 50 ]
  grep -F "order-limit-75-${CASE_SUFFIX}" "$RESP_FILE" >/dev/null
  grep -F "order-limit-26-${CASE_SUFFIX}" "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_order_limit"

# Cleanup — remove seeded DB rows.
