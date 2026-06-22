#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-order-pending-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
ORDER_ID="order-pending-${CASE_SUFFIX}"
PRODUCT_ID="prod-pending-${CASE_SUFFIX}"
ORDER_ITEM_ID="oi-pending-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/order_not_ready_to_ship_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/order_not_ready_to_ship_response_${CASE_SUFFIX}.json"
TOKEN_FILE="/tmp/order_not_ready_to_ship_token_${CASE_SUFFIX}.txt"

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

# Given — create an active seller and a PENDING order with one of the seller's items.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Pending ${CASE_SUFFIX}\",\"bio\":\"Bio\"}")"
[ "$REGISTER_STATUS" = "201" ]
SELLER_TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_RESPONSE" | head -1 | cut -d '"' -f4)"
printf '%s' "$SELLER_TOKEN" > "$TOKEN_FILE"
SELLER_USER_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}' LIMIT 1;")"
SELLER_PROFILE_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"SellerProfile\" WHERE \"userId\" = '${SELLER_USER_ID}' LIMIT 1;")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible)
VALUES ('${PRODUCT_ID}', '${SELLER_PROFILE_ID}', 'Pending Product ${CASE_SUFFIX}', 'Pending product', 'general', 1300, 2, '[]', 'ACTIVE', true);
INSERT INTO "Order" (id, status)
VALUES ('${ORDER_ID}', 'PENDING');
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1000);
SQL

# When — POST /orders/:id/ship for a non-shippable order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")")"

# Then — HTTP 400 and order stays PENDING.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":"Order not ready to ship"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "PENDING" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:order_not_ready_to_ship"
