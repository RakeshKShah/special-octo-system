#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/buyer_register_happy_path_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure unique buyer email and DB connectivity
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true

# When — register a buyer
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"BuyerPass123!\",\"role\":\"BUYER\"}")"

# Then — assert 201 and active buyer without seller profile
[ "$HTTP_STATUS" = "201" ]
jq -e '.token | type == "string" and length > 0' "$RESPONSE_FILE" >/dev/null
jq -e --arg email "$EMAIL" '.user.email == $email' "$RESPONSE_FILE" >/dev/null
jq -e '.user.role == "BUYER"' "$RESPONSE_FILE" >/dev/null
jq -e '.user.status == "ACTIVE"' "$RESPONSE_FILE" >/dev/null
jq -e '.user.sellerProfile == null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:buyer_register_happy_path"

# Cleanup — handled by trap
