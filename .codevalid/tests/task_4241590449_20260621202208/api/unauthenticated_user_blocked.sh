#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
ORDER_ID="order-unauth-${CASE_SUFFIX}"
BUYER_EMAIL="unauth_buyer_${CASE_SUFFIX}@example.com"
BUYER_FILE="/tmp/unauthenticated_user_blocked_buyer_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/unauthenticated_user_blocked_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Order\" WHERE id = '${ORDER_ID}'; DELETE FROM \"User\" WHERE email = '${BUYER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$BUYER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — create a buyer and seed a PAID order, but do not send credentials.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
BUYER_STATUS="$(curl -sS -o "$BUYER_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"
[ "$BUYER_STATUS" = "201" ]
BUYER_USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$BUYER_FILE" | head -n1)"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Order\" (id, \"buyerId\", status, total, \"createdAt\", \"updatedAt\") VALUES ('${ORDER_ID}', '${BUYER_USER_ID}', 'PAID', 12, NOW(), NOW());" >/dev/null

# When — call ship endpoint without Authorization header.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/${ORDER_ID}/ship")"

# Then — expect 401 authentication failure.
[ "$HTTP_STATUS" = "401" ]
grep -E '"error":"Unauthorized"|"error":"Invalid token"' "$RESPONSE_FILE" >/dev/null

# Cleanup — handled by trap.
echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_user_blocked"
