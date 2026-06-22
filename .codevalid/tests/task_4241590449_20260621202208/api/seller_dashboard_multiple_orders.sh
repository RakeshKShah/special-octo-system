#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_multiple_orders_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
BUYER1_EMAIL="alice_${CASE_SUFFIX}@test.com"
BUYER2_EMAIL="bob_${CASE_SUFFIX}@test.com"
STORE_NAME="Multi Order Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id IN ('item-m1-${CASE_SUFFIX}','item-m2-${CASE_SUFFIX}');
DELETE FROM "Order" WHERE id IN ('order-m1-${CASE_SUFFIX}','order-m2-${CASE_SUFFIX}');
DELETE FROM "Product" WHERE id IN ('prod-m1-${CASE_SUFFIX}','prod-m2-${CASE_SUFFIX}');
DELETE FROM "User" WHERE email IN ('${BUYER1_EMAIL}','${BUYER2_EMAIL}');
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create active seller, two products, and two buyer orders with distinct details.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Multiple orders\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "User" (id, email, "passwordHash", role, status, "createdAt", "updatedAt") VALUES
('buyer1-${CASE_SUFFIX}', '${BUYER1_EMAIL}', 'seeded-hash', 'BUYER', 'ACTIVE', NOW(), NOW()),
('buyer2-${CASE_SUFFIX}', '${BUYER2_EMAIL}', 'seeded-hash', 'BUYER', 'ACTIVE', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt") VALUES
('prod-m1-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Product A', 'A desc', 'HOME', 1000, 5, '["https://example.test/a.jpg"]', 'ACTIVE', true, NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes'),
('prod-m2-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Product B', 'B desc', 'HOME', 2000, 5, '["https://example.test/b.jpg"]', 'ACTIVE', true, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute');
INSERT INTO "Order" (id, "buyerId", status, "createdAt", "updatedAt") VALUES
('order-m1-${CASE_SUFFIX}', 'buyer1-${CASE_SUFFIX}', 'PAID', NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes'),
('order-m2-${CASE_SUFFIX}', 'buyer2-${CASE_SUFFIX}', 'SHIPPED', NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute');
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents", "createdAt", "updatedAt") VALUES
('item-m1-${CASE_SUFFIX}', 'order-m1-${CASE_SUFFIX}', 'prod-m1-${CASE_SUFFIX}', 1, 1000, NOW() - INTERVAL '2 minutes', NOW() - INTERVAL '2 minutes'),
('item-m2-${CASE_SUFFIX}', 'order-m2-${CASE_SUFFIX}', 'prod-m2-${CASE_SUFFIX}', 3, 2000, NOW() - INTERVAL '1 minute', NOW() - INTERVAL '1 minute');
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — dashboard shows both orders with required fields and values.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq '.orders | length' "$RESP_FILE")" = "2" ]
  jq -e '.orders[] | select(.product_title=="Product A" and .qty==1 and .buyer_email=="'"$BUYER1_EMAIL"'" and .order_status=="PAID" and .seller_payout_cents==1000 and .created_at!=null)' "$RESP_FILE" >/dev/null
  jq -e '.orders[] | select(.product_title=="Product B" and .qty==3 and .buyer_email=="'"$BUYER2_EMAIL"'" and .order_status=="SHIPPED" and .seller_payout_cents==2000 and .created_at!=null)' "$RESP_FILE" >/dev/null
else
  grep -F 'Product A' "$RESP_FILE" >/dev/null
  grep -F 'Product B' "$RESP_FILE" >/dev/null
  grep -F "$BUYER1_EMAIL" "$RESP_FILE" >/dev/null
  grep -F "$BUYER2_EMAIL" "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_multiple_orders"

# Cleanup — remove seeded DB rows.
