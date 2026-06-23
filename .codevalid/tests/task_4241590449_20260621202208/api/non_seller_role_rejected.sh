#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="nonseller_${CASE_SUFFIX}@example.com"
ORDER_ID="order-nonseller-${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}.json"
REGISTER_FILE="/tmp/non_seller_role_rejected_register_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Order\" WHERE id = '${ORDER_ID}'; DELETE FROM \"User\" WHERE email = '${BUYER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE"
}
trap cleanup EXIT

# Given — create an active BUYER user and a PAID order.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
HTTP_REGISTER="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"
[ "$HTTP_REGISTER" = "201" ]
BUYER_TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n1)"
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '${BUYER_USER_ID}'; INSERT INTO \"Order\" (id, \"buyerId\", status, total, \"createdAt\", \"updatedAt\") VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 10, NOW(), NOW());" >/dev/null

# When — attempt to ship as a non-seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship" -H "Authorization: Bearer ${BUYER_TOKEN}")"

# Then — expect 403 Active seller required.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Active seller required"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_rejected"
