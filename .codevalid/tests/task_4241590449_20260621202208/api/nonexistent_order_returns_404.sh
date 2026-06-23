#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_missing_${CASE_SUFFIX}@example.com"
STORE_NAME="Missing Order Store ${CASE_SUFFIX}"
ORDER_ID="nonexistent-order-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/nonexistent_order_returns_404_${CASE_SUFFIX}.json"
SELLER_FILE="/tmp/nonexistent_order_returns_404_seller_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"storeName\" = '${STORE_NAME}'; DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$SELLER_FILE"
}
trap cleanup EXIT

# Given — create an active seller and ensure the order id does not exist.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
SELLER_HTTP_STATUS="$(curl -sS -o "$SELLER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"seeded seller\"}")"
[ "$SELLER_HTTP_STATUS" = "201" ]
SELLER_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$SELLER_FILE" | head -n1)"
SELLER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$SELLER_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}'; DELETE FROM \"Order\" WHERE id = '${ORDER_ID}';" >/dev/null

# When — attempt to ship a missing order.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${SELLER_TOKEN}")"

# Then — expect 404 Order not found.
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Order not found"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:nonexistent_order_returns_404"
