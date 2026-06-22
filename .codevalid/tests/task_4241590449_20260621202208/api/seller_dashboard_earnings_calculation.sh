#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_earnings_calculation_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
BUYER_EMAIL="buyer_${CASE_SUFFIX}@example.com"
STORE_NAME="Earnings Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id IN ('item-e1-${CASE_SUFFIX}','item-e2-${CASE_SUFFIX}','item-e3-${CASE_SUFFIX}');
DELETE FROM "Order" WHERE id IN ('order-e1-${CASE_SUFFIX}','order-e2-${CASE_SUFFIX}','order-e3-${CASE_SUFFIX}');
DELETE FROM "Product" WHERE id = 'prod-earn-${CASE_SUFFIX}';
DELETE FROM "User" WHERE email = '${BUYER_EMAIL}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create active seller with three order items totalling 4600 payout cents.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Revenue test\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "User" (id, email, "passwordHash", role, status, "createdAt", "updatedAt")
VALUES ('buyer-${CASE_SUFFIX}', '${BUYER_EMAIL}', 'seeded-hash', 'BUYER', 'ACTIVE', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
VALUES ('prod-earn-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Profit Item', 'Profit product', 'HOME', 2000, 10, '["https://example.test/profit.jpg"]', 'ACTIVE', true, NOW(), NOW());
INSERT INTO "Order" (id, "buyerId", status, "createdAt", "updatedAt") VALUES
('order-e1-${CASE_SUFFIX}', 'buyer-${CASE_SUFFIX}', 'PAID', NOW(), NOW()),
('order-e2-${CASE_SUFFIX}', 'buyer-${CASE_SUFFIX}', 'PAID', NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute'),
('order-e3-${CASE_SUFFIX}', 'buyer-${CASE_SUFFIX}', 'PAID', NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes');
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents", "createdAt", "updatedAt") VALUES
('item-e1-${CASE_SUFFIX}', 'order-e1-${CASE_SUFFIX}', 'prod-earn-${CASE_SUFFIX}', 1, 1500, NOW(), NOW()),
('item-e2-${CASE_SUFFIX}', 'order-e2-${CASE_SUFFIX}', 'prod-earn-${CASE_SUFFIX}', 1, 2300, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute'),
('item-e3-${CASE_SUFFIX}', 'order-e3-${CASE_SUFFIX}', 'prod-earn-${CASE_SUFFIX}', 1, 800, NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes');
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — total_earnings_cents equals 4600.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.total_earnings_cents' "$RESP_FILE")" = "4600" ]
else
  grep -F '4600' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_earnings_calculation"

# Cleanup — remove seeded DB rows.
