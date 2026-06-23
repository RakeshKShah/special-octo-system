#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-default-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_register_defaults_store_profile_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure unique seller email and DB connectivity
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true

# When — register a seller without storeName and bio
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\"}")"

# Then — assert default sellerProfile values
[ "$HTTP_STATUS" = "201" ]
jq -e '.token | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null
jq -e '.user.role == "SELLER"' "$RESPONSE_FILE" >/dev/null
jq -e '.user.status == "PENDING"' "$RESPONSE_FILE" >/dev/null
jq -e '.user.sellerProfile.storeName == "My Shop"' "$RESPONSE_FILE" >/dev/null
jq -e '.user.sellerProfile.bio == ""' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_defaults_store_profile"

# Cleanup — handled by trap
