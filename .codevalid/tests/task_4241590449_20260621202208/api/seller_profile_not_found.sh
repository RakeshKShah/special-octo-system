#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_no_profile_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_FILE="/tmp/seller_profile_not_found_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_profile_not_found_${CASE_SUFFIX}.json"
TOKEN=""
USER_ID=""
SELLER_PROFILE_ID=""

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

# Given — register a seller, promote it to ACTIVE, and remove its seller profile row.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"No Profile Store ${CASE_SUFFIX}\",\"bio\":\"Temp\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null 2>&1 || \
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE id = '$SELLER_PROFILE_ID';" >/dev/null 2>&1 || \
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '$SELLER_PROFILE_ID';" >/dev/null

# When — attempt to create a product with an active seller account that lacks a profile row.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data '{"title":"Profile Missing Product","description":"desc","category":"HOME","price_cents":2500,"stock_qty":1,"photos":[]}')"

# Then — status 404 and seller profile not found are returned.
[ "$HTTP_STATUS" = "404" ]
jq -e '.error == "Seller profile not found"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found"

# Cleanup — delete remaining seller user row.
