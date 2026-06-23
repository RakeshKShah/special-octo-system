#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="inactive_seller_${CASE_SUFFIX}@example.com"
BUYER_EMAIL="inactive_buyer_${CASE_SUFFIX}@example.com"
STORE_NAME="Inactive Store ${CASE_SUFFIX}"
PRODUCT_TITLE="Inactive Product ${CASE_SUFFIX}"
ORDER_ID="order-inactive-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/inactive_seller_rejected_${CASE_SUFFIX}.json"
SELLER_FILE="/tmp/inactive_seller_rejected_seller_${CASE_SUFFIX}.json"
BUYER_FILE="/tmp/inactive_seller_rejected_buyer_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "OrderItem" WHERE "orderId" = '${ORDER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "Product" WHERE title = '${PRODUCT_TITLE}';
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email IN ('${SELLER_EMAIL}', '${BUYER_EMAIL}');
SQL
  rm -f "$RESPONSE_FILE" "$SELLER_FILE" "$BUYER_FILE"
}
trap cleanup EXIT

# Given — create a pending seller and buyer, then seed a product and PAID order for that seller directly in the database.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
SELLER_HTTP_STATUS="$(curl -sS -o "$SELLER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"seeded seller\"}")"
[ "$SELLER_HTTP_STATUS" = "201" ]
SELLER_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$SELLER_FILE" | head -n1)"
SELLER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$SELLER_FILE" | head -n1)"
BUYER_HTTP_STATUS="$(curl -sS -o "$BUYER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"
[ "$BUYER_HTTP_STATUS" = "201" ]
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$BUYER_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt")
VALUES ('prod-inactive-${CASE_SUFFIX}', (SELECT id FROM "SellerProfile" WHERE "userId" = '${SELLER_USER_ID}'), '${PRODUCT_TITLE}', 'desc', 'general', 1800, 2, ARRAY['https://example.com/${CASE_SUFFIX}.jpg'], 'ACTIVE', true, NOW(), NOW());
INSERT INTO "Order" (id, "buyerId", status, total, "createdAt", "updatedAt")
VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 18, NOW(), NOW());
INSERT INTO "OrderItem" (id, "orderId", "productId", qty, "sellerPayoutCents")
VALUES ('oi-inactive-${CASE_SUFFIX}', '${ORDER_ID}', 'prod-inactive-${CASE_SUFFIX}', 1, 1500);
SQL

# When — attempt to ship as a non-active seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${SELLER_TOKEN}")"

# Then — expect 403 Active seller required.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Active seller required"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:inactive_seller_rejected"
