#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-ship-idempotent-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
ORDER_ID="order-shipped-${CASE_SUFFIX}"
PRODUCT_ID="prod-shipped-${CASE_SUFFIX}"
ORDER_ITEM_ID="oi-shipped-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/idempotent_ship_already_shipped_order_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/idempotent_ship_already_shipped_order_response_${CASE_SUFFIX}.json"
TOKEN_FILE="/tmp/idempotent_ship_already_shipped_order_token_${CASE_SUFFIX}.txt"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE "userId" IN (SELECT id FROM "User" WHERE email = '${SELLER_EMAIL}');
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given — create an active seller and an order already marked SHIPPED with that seller's item.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Idempotent ${CASE_SUFFIX}\",\"bio\":\"Bio\"}")"
[ "$REGISTER_STATUS" = "201" ]
SELLER_TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_RESPONSE" | head -1 | cut -d '"' -f4)"
printf '%s' "$SELLER_TOKEN" > "$TOKEN_FILE"
SELLER_USER_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}' LIMIT 1;")"
SELLER_PROFILE_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"SellerProfile\" WHERE \"userId\" = '${SELLER_USER_ID}' LIMIT 1;")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Shipped Product ${CASE_SUFFIX}', 'Shipped product', 'general', 2100, 4, '[]', 'ACTIVE', true);
INSERT INTO "Order" (id, status)
VALUES ('${ORDER_ID}', 'SHIPPED');
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1800);
SQL

# When — POST /orders/:id/ship again for an already shipped order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")")"

# Then — HTTP 200 with SHIPPED and DB remains SHIPPED.
[ "$HTTP_STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SHIPPED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "SHIPPED" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:idempotent_ship_already_shipped_order"
