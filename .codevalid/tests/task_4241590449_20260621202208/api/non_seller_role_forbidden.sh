#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer_${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_FILE="/tmp/non_seller_role_forbidden_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/non_seller_role_forbidden_${CASE_SUFFIX}.json"
TOKEN=""
USER_ID=""

cleanup() {
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register a BUYER account and use its token.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${BUYER_EMAIL}\",\"password\":\"${BUYER_PASSWORD}\",\"role\":\"BUYER\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"

# When — attempt to create a product as a non-seller.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Any Product","description":"desc","category":"HOME","price_cents":2500,"stock_qty":1,"photos":[]}')"

# Then — status 403 and seller access error are returned.
[ "$HTTP_STATUS" = "403" ]
jq -e '.error == "Seller access required"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_forbidden"

# Cleanup — delete created buyer user row.
