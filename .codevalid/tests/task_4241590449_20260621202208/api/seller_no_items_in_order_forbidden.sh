#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-no-items-${CASE_SUFFIX}@example.com"
OTHER_SELLER_EMAIL="other-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!"
ORDER_ID="order-other-items-${CASE_SUFFIX}"
PRODUCT_ID="prod-other-items-${CASE_SUFFIX}"
ORDER_ITEM_ID="oi-other-items-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/seller_no_items_in_order_forbidden_register_${CASE_SUFFIX}.json"
OTHER_REGISTER_RESPONSE="/tmp/seller_no_items_in_order_forbidden_other_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_no_items_in_order_forbidden_response_${CASE_SUFFIX}.json"
TOKEN_FILE="/tmp/seller_no_items_in_order_forbidden_token_${CASE_SUFFIX}.txt"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE id = '${ORDER_ITEM_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE id = '${PRODUCT_ID}';
DELETE FROM "SellerProfile" WHERE "userId" IN (SELECT id FROM "User" WHERE email IN ('${SELLER_EMAIL}', '${OTHER_SELLER_EMAIL}'));
DELETE FROM "User" WHERE email IN ('${SELLER_EMAIL}', '${OTHER_SELLER_EMAIL}');
SQL
  rm -f "$REGISTER_RESPONSE" "$OTHER_REGISTER_RESPONSE" "$RESPONSE_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given — create two active sellers; seed a PAID order containing only the other seller's product.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Primary ${CASE_SUFFIX}\",\"bio\":\"Bio\"}")"
[ "$REGISTER_STATUS" = "201" ]
SELLER_TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_RESPONSE" | head -1 | cut -d '"' -f4)"
printf '%s' "$SELLER_TOKEN" > "$TOKEN_FILE"
OTHER_STATUS="$(curl -sS -o "$OTHER_REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${OTHER_SELLER_EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Other ${CASE_SUFFIX}\",\"bio\":\"Bio\"}")"
[ "$OTHER_STATUS" = "201" ]
SELLER_USER_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}' LIMIT 1;")"
OTHER_USER_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"User\" WHERE email = '${OTHER_SELLER_EMAIL}' LIMIT 1;")"
OTHER_PROFILE_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"SellerProfile\" WHERE \"userId\" = '${OTHER_USER_ID}' LIMIT 1;")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id IN ('${SELLER_USER_ID}', '${OTHER_USER_ID}');
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible)
VALUES ('${PRODUCT_ID}', '${OTHER_PROFILE_ID}', 'Other Product ${CASE_SUFFIX}', 'Other product', 'general', 1700, 5, '[]', 'ACTIVE', true);
INSERT INTO "Order" (id, status)
VALUES ('${ORDER_ID}', 'PAID');
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('${ORDER_ITEM_ID}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1300);
SQL

# When — POST /orders/:id/ship as a seller with no items in the order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")")"

# Then — HTTP 403 and order remains PAID.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"No items for your shop in this order"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "PAID" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:seller_no_items_in_order_forbidden"
