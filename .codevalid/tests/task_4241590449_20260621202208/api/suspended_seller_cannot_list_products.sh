#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="suspended_seller_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_FILE="/tmp/suspended_seller_cannot_list_products_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/suspended_seller_cannot_list_products_${CASE_SUFFIX}.json"
TOKEN=""
USER_ID=""

cleanup() {
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register a seller and set its database status to SUSPENDED.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Suspended Store ${CASE_SUFFIX}\",\"bio\":\"Suspended\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'SUSPENDED' WHERE id = '$USER_ID';" >/dev/null 2>&1 || \
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'SUSPENDED' WHERE id = '$USER_ID';" >/dev/null

# When — attempt to create a product as a suspended seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Blocked Product","description":"desc","category":"HOME","price_cents":2500,"stock_qty":1,"photos":[]}')"

# Then — status 403 and suspended-seller error are returned.
[ "$HTTP_STATUS" = "403" ]
jq -e '.error == "Suspended sellers cannot create products"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_cannot_list_products"

# Cleanup — delete created seller profile and user rows.
