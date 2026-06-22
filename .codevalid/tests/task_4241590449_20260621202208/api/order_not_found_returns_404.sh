#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-order-missing-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
ORDER_ID="nonexistent-order-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/order_not_found_returns_404_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/order_not_found_returns_404_response_${CASE_SUFFIX}.json"
TOKEN_FILE="/tmp/order_not_found_returns_404_token_${CASE_SUFFIX}.txt"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE "userId" IN (SELECT id FROM "User" WHERE email = '${SELLER_EMAIL}');
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given — create and activate a seller account; ensure target order does not exist.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Missing ${CASE_SUFFIX}\",\"bio\":\"Bio\"}")"
[ "$REGISTER_STATUS" = "201" ]
SELLER_TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_RESPONSE" | head -1 | cut -d '"' -f4)"
printf '%s' "$SELLER_TOKEN" > "$TOKEN_FILE"
SELLER_USER_ID="$(psql "$DATABASE_URL" -At -c "SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}' LIMIT 1;")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
SQL

# When — POST /orders/:id/ship for a nonexistent order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")")"

# Then — HTTP 404 and Order not found.
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Order not found"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:order_not_found_returns_404"
