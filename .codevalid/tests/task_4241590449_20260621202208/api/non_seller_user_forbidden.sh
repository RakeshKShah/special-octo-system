#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer-ship-forbidden-${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Password123!"
ORDER_ID="order-buyer-forbidden-${CASE_SUFFIX}"
REGISTER_RESPONSE="/tmp/non_seller_user_forbidden_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/non_seller_user_forbidden_response_${CASE_SUFFIX}.json"
TOKEN_FILE="/tmp/non_seller_user_forbidden_token_${CASE_SUFFIX}.txt"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "Order" WHERE id = '${ORDER_ID}';
DELETE FROM "User" WHERE email = '${BUYER_EMAIL}';
SQL
  rm -f "$REGISTER_RESPONSE" "$RESPONSE_FILE" "$TOKEN_FILE"
}
trap cleanup EXIT

# Given — create an ACTIVE BUYER account and seed a PAID order.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}")"
[ "$REGISTER_STATUS" = "201" ]
BUYER_TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_RESPONSE" | head -1 | cut -d '"' -f4)"
printf '%s' "$BUYER_TOKEN" > "$TOKEN_FILE"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Order\" (id, status) VALUES ('${ORDER_ID}', 'PAID');" >/dev/null

# When — POST /orders/:id/ship as a buyer.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/${ORDER_ID}/ship" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")")"

# Then — HTTP 403 with Active seller required and order remains PAID.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Active seller required"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -At -c "SELECT status FROM \"Order\" WHERE id = '${ORDER_ID}';")"
[ "$DB_STATUS" = "PAID" ]

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_user_forbidden"
