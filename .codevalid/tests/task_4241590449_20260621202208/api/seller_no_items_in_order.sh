#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER1_EMAIL="seller_a_${CASE_SUFFIX}@example.com"
SELLER2_EMAIL="seller_b_${CASE_SUFFIX}@example.com"
BUYER_EMAIL="buyer_no_items_${CASE_SUFFIX}@example.com"
STORE1_NAME="Store A ${CASE_SUFFIX}"
STORE2_NAME="Store B ${CASE_SUFFIX}"
PRODUCT2_TITLE="Only Seller2 Product ${CASE_SUFFIX}"
ORDER_ID="order-no-items-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/seller_no_items_in_order_${CASE_SUFFIX}.json"
SELLER1_FILE="/tmp/seller_no_items_in_order_s1_${CASE_SUFFIX}.json"
SELLER2_FILE="/tmp/seller_no_items_in_order_s2_${CASE_SUFFIX}.json"
BUYER_FILE="/tmp/seller_no_items_in_order_b_${CASE_SUFFIX}.json"
PRODUCT_FILE="/tmp/seller_no_items_in_order_p_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE title = '${PRODUCT2_TITLE}';
DELETE FROM "SellerProfile" WHERE "storeName" IN ('${STORE1_NAME}', '${STORE2_NAME}');
DELETE FROM "User" WHERE email IN ('${SELLER1_EMAIL}', '${SELLER2_EMAIL}', '${BUYER_EMAIL}');
SQL
  rm -f "$RESPONSE_FILE" "$SELLER1_FILE" "$SELLER2_FILE" "$BUYER_FILE" "$PRODUCT_FILE"
}
trap cleanup EXIT

# Given — create two active sellers and a buyer, create product only for seller 2, seed PAID order with no seller 1 items.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
S1_STATUS="$(curl -sS -o "$SELLER1_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER1_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE1_NAME}\",\"bio\":\"seller1\"}")"; [ "$S1_STATUS" = "201" ]
S2_STATUS="$(curl -sS -o "$SELLER2_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER2_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE2_NAME}\",\"bio\":\"seller2\"}")"; [ "$S2_STATUS" = "201" ]
S1_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$SELLER1_FILE" | head -n1)"
S1_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$SELLER1_FILE" | head -n1)"
S2_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$SELLER2_FILE" | head -n1)"
S2_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$SELLER2_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id IN ('${S1_USER_ID}','${S2_USER_ID}');" >/dev/null
BUYER_STATUS="$(curl -sS -o "$BUYER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"; [ "$BUYER_STATUS" = "201" ]
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$BUYER_FILE" | head -n1)"
PRODUCT_STATUS="$(curl -sS -o "$PRODUCT_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" -H "Authorization: Bearer ${S2_TOKEN}" -H 'Content-Type: application/json' --data "{\"title\":\"${PRODUCT2_TITLE}\",\"description\":\"desc\",\"category\":\"general\",\"price_cents\":2400,\"stock_qty\":2,\"photos\":[\"https://example.com/${CASE_SUFFIX}.jpg\"]}")"; [ "$PRODUCT_STATUS" = "201" ]
PRODUCT2_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$PRODUCT_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
INSERT INTO "Order" (id, "buyerId", status, total, "createdAt", "updatedAt")
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 24, NOW(), NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('oi-no-items-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT2_ID}', 1, 1800);
SQL

# When — seller 1 attempts to ship an order that contains only seller 2 items.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${S1_TOKEN}")"

# Then — expect 403 No items for your shop in this order.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"No items for your shop in this order"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:seller_no_items_in_order"
