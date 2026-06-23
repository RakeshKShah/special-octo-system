#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_FILE="/tmp/non_seller_role_rejected_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/non_seller_role_rejected_${CASE_SUFFIX}.json"
USER_ID=""
TOKEN=""

cleanup() {
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
  else
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register a unique BUYER account.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]

# When — attempt to create a product as a non-seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Test Product","description":"Test","category":"Misc","price_cents":1000,"stock_qty":1,"photos":[]}')"

# Then — response is 403 with seller access required.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_rejected"

# Cleanup — remove the created buyer account.
