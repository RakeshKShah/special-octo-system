#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_happy_path_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
BUYER_EMAIL="buyer_${CASE_SUFFIX}@example.com"
STORE_NAME="Artisan Crafts ${CASE_SUFFIX}"
STORE_BIO="Handmade goods"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

json_get() {
  key="$1"
  file="$2"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$key" "$file"
  else
    cat "$file"
  fi
}

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id = 'item-${CASE_SUFFIX}';
DELETE FROM "Order" WHERE id = 'order-${CASE_SUFFIX}';
DELETE FROM "Product" WHERE id IN ('prod-111-${CASE_SUFFIX}','prod-112-${CASE_SUFFIX}');
DELETE FROM "User" WHERE email = '${BUYER_EMAIL}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create seller, activate seller, seed products, buyer, order and order item.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${STORE_BIO}\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "User" (id, email, "passwordHash", role, status, "createdAt", "updatedAt")
VALUES ('buyer-${CASE_SUFFIX}', '${BUYER_EMAIL}', 'seeded-hash', 'BUYER', 'ACTIVE', NOW(), NOW());
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
VALUES
('prod-111-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Ceramic Mug', 'Handmade mug', 'HOME', 2500, 10, '["https://example.test/mug.jpg"]', 'ACTIVE', true, NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 days'),
('prod-112-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Wooden Bowl', 'Handmade bowl', 'HOME', 4500, 5, '["https://example.test/bowl.jpg"]', 'ACTIVE', true, NOW() - INTERVAL '1 day', NOW() - INTERVAL '1 day');
INSERT INTO "Order" (id, "buyerId", status, "createdAt", "updatedAt")
VALUES ('order-${CASE_SUFFIX}', 'buyer-${CASE_SUFFIX}', 'PAID', NOW(), NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents", "createdAt", "updatedAt")
VALUES ('item-${CASE_SUFFIX}', 'order-${CASE_SUFFIX}', 'prod-111-${CASE_SUFFIX}', 2, 5000, NOW(), NOW());
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — response is 200 and contains expected store, products, order row, and earnings.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.store_name' "$RESP_FILE")" = "$STORE_NAME" ]
  [ "$(jq -r '.bio' "$RESP_FILE")" = "$STORE_BIO" ]
  [ "$(jq -r '.status' "$RESP_FILE")" = "ACTIVE" ]
  [ "$(jq '.products | length' "$RESP_FILE")" = "2" ]
  [ "$(jq -r '.orders[0].product_title' "$RESP_FILE")" = "Ceramic Mug" ]
  [ "$(jq -r '.orders[0].buyer_email' "$RESP_FILE")" = "$BUYER_EMAIL" ]
  [ "$(jq -r '.orders[0].qty' "$RESP_FILE")" = "2" ]
  [ "$(jq -r '.total_earnings_cents' "$RESP_FILE")" = "5000" ]
else
  grep -F 'Ceramic Mug' "$RESP_FILE" >/dev/null
  grep -F 'Wooden Bowl' "$RESP_FILE" >/dev/null
  grep -F "$BUYER_EMAIL" "$RESP_FILE" >/dev/null
  grep -F '5000' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_happy_path"

# Cleanup — remove seeded DB rows.
