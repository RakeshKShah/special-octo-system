#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer1-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/non_seller_register_active_status_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure unique buyer email is absent
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null

# When — register a BUYER
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"BUYER\"}")"

# Then — response is 201 with ACTIVE status and no sellerProfile
[ "$HTTP_STATUS" = "201" ]
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"role":"BUYER"' "$RESPONSE_FILE" >/dev/null
grep -F '"sellerProfile":null' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_register_active_status"

# Cleanup — remove created user row
