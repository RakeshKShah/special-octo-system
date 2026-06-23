#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_paid_${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer_paid_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
BUYER_PASSWORD="Password123!"
STORE_NAME="Paid Store ${CASE_SUFFIX}"
PRODUCT_TITLE="Paid Product ${CASE_SUFFIX}"
ORDER_ID="order-paid-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_marks_paid_order_as_shipped_${CASE_SUFFIX}.json"
REGISTER_FILE="/tmp/seller_marks_paid_order_as_shipped_register_${CASE_SUFFIX}.json"
BUYER_FILE="/tmp/seller_marks_paid_order_as_shipped_buyer_${CASE_SUFFIX}.json"
PRODUCT_FILE="/tmp/seller_marks_paid_order_as_shipped_product_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE title = '${PRODUCT_TITLE}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email IN ('${SELLER_EMAIL}', '${BUYER_EMAIL}');
SQL
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE" "$BUYER_FILE" "$PRODUCT_FILE"
}
trap cleanup EXIT

# Given — create active seller and buyer, create seller product, seed a PAID order containing the seller item.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
SELLER_HTTP_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"seeded seller\"}")"
[ "$SELLER_HTTP_STATUS" = "201" ]
SELLER_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n1)"
SELLER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';" >/dev/null

BUYER_HTTP_STATUS="$(curl -sS -o "$BUYER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}")"
[ "$BUYER_HTTP_STATUS" = "201" ]
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$BUYER_FILE" | head -n1)"

PRODUCT_HTTP_STATUS="$(curl -sS -o "$PRODUCT_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" -H "Authorization: Bearer ${SELLER_TOKEN}" -H 'Content-Type: application/json' --data "{\"title\":\"${PRODUCT_TITLE}\",\"description\":\"desc\",\"category\":\"general\",\"price_cents\":1500,\"stock_qty\":3,\"photos\":[\"https://example.com/${CASE_SUFFIX}.jpg\"]}")"
[ "$PRODUCT_HTTP_STATUS" = "201" ]
PRODUCT_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$PRODUCT_FILE" | head -n1)"

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
INSERT INTO "Order" (id, "buyerId", status, total, "createdAt", "updatedAt")
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 15, NOW(), NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('oi-paid-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT_ID}', 1, 1200);
SQL

# When — ship the PAID order as the active seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${SELLER_TOKEN}")"

# Then — expect 200, success true, SHIPPED status, and database status updated.
[ "$HTTP_STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SHIPPED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "SHIPPED" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:seller_marks_paid_order_as_shipped"
