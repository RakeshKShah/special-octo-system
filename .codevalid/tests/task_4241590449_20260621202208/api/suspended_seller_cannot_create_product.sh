#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="suspended-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Suspended Shop ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/suspended_seller_cannot_create_product_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/suspended_seller_cannot_create_product_${CASE_SUFFIX}.json"
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

# Given — register a unique seller, then mark the seller as SUSPENDED in the database.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"suspended\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'SUSPENDED' WHERE id = '${USER_ID}';" >/dev/null

# When — attempt to create a product as a suspended seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Test Product","description":"Test","category":"Misc","price_cents":1000,"stock_qty":1,"photos":[]}')"

# Then — response is 403 with suspended-seller error.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Suspended sellers cannot create products"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_cannot_create_product"

# Cleanup — remove the created suspended seller account.
