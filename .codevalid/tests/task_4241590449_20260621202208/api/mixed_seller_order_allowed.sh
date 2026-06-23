#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER1_EMAIL="mixed_seller1_${CASE_SUFFIX}@example.com"
SELLER2_EMAIL="mixed_seller2_${CASE_SUFFIX}@example.com"
BUYER_EMAIL="mixed_buyer_${CASE_SUFFIX}@example.com"
STORE1_NAME="Mixed Store A ${CASE_SUFFIX}"
STORE2_NAME="Mixed Store B ${CASE_SUFFIX}"
PRODUCT1_TITLE="Mixed Product A ${CASE_SUFFIX}"
PRODUCT2_TITLE="Mixed Product B ${CASE_SUFFIX}"
ORDER_ID="order-mixed-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/mixed_seller_order_allowed_${CASE_SUFFIX}.json"
S1_FILE="/tmp/mixed_seller_order_allowed_s1_${CASE_SUFFIX}.json"
S2_FILE="/tmp/mixed_seller_order_allowed_s2_${CASE_SUFFIX}.json"
BUYER_FILE="/tmp/mixed_seller_order_allowed_b_${CASE_SUFFIX}.json"
P1_FILE="/tmp/mixed_seller_order_allowed_p1_${CASE_SUFFIX}.json"
P2_FILE="/tmp/mixed_seller_order_allowed_p2_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE title IN ('${PRODUCT1_TITLE}', '${PRODUCT2_TITLE}');
DELETE FROM "SellerProfile" WHERE "storeName" IN ('${STORE1_NAME}', '${STORE2_NAME}');
DELETE FROM "User" WHERE email IN ('${SELLER1_EMAIL}', '${SELLER2_EMAIL}', '${BUYER_EMAIL}');
SQL
  rm -f "$RESPONSE_FILE" "$S1_FILE" "$S2_FILE" "$BUYER_FILE" "$P1_FILE" "$P2_FILE"
}
trap cleanup EXIT

# Given — create two active sellers and a buyer, create one product per seller, seed a PAID mixed-seller order.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
S1_STATUS="$(curl -sS -o "$S1_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER1_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE1_NAME}\",\"bio\":\"seller1\"}")"; [ "$S1_STATUS" = "201" ]
S2_STATUS="$(curl -sS -o "$S2_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER2_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE2_NAME}\",\"bio\":\"seller2\"}")"; [ "$S2_STATUS" = "201" ]
S1_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$S1_FILE" | head -n1)"
S2_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$S2_FILE" | head -n1)"
S1_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$S1_FILE" | head -n1)"
S2_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$S2_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id IN ('${S1_USER_ID}','${S2_USER_ID}');" >/dev/null
BUYER_STATUS="$(curl -sS -o "$BUYER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"; [ "$BUYER_STATUS" = "201" ]
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$BUYER_FILE" | head -n1)"
P1_STATUS="$(curl -sS -o "$P1_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" -H "Authorization: Bearer ${S1_TOKEN}" -H 'Content-Type: application/json' --data "{\"title\":\"${PRODUCT1_TITLE}\",\"description\":\"desc\",\"category\":\"general\",\"price_cents\":2000,\"stock_qty\":3,\"photos\":[\"https://example.com/${CASE_SUFFIX}-a.jpg\"]}")"; [ "$P1_STATUS" = "201" ]
P2_STATUS="$(curl -sS -o "$P2_FILE" -w '%{http_code}' -X POST "$BASE_URL/products" -H "Authorization: Bearer ${S2_TOKEN}" -H 'Content-Type: application/json' --data "{\"title\":\"${PRODUCT2_TITLE}\",\"description\":\"desc\",\"category\":\"general\",\"price_cents\":3000,\"stock_qty\":3,\"photos\":[\"https://example.com/${CASE_SUFFIX}-b.jpg\"]}")"; [ "$P2_STATUS" = "201" ]
PRODUCT1_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$P1_FILE" | head -n1)"
PRODUCT2_ID="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$P2_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
INSERT INTO "Order" (id, "buyerId", status, total, "createdAt", "updatedAt")
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 50, NOW(), NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('oi-mixed-a-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT1_ID}', 1, 1500),
       ('oi-mixed-b-${CASE_SUFFIX}', '${ORDER_ID}', '${PRODUCT2_ID}', 1, 2300);
SQL

# When — seller 1 ships the mixed-seller order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${S1_TOKEN}")"

# Then — expect 200 success and DB status SHIPPED.
[ "$HTTP_STATUS" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SHIPPED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -t -A -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "SHIPPED" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:mixed_seller_order_allowed"
