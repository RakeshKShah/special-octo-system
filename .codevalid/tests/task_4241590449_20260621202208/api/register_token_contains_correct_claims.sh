#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller7-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/register_token_contains_correct_claims_${CASE_SUFFIX}.json"
PAYLOAD_FILE="/tmp/register_token_contains_correct_claims_payload_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

b64url_decode() {
  value="$1"
  pad=$(( (4 - ${#value} % 4) % 4 ))
  while [ "$pad" -gt 0 ]; do
    value="${value}="
    pad=$((pad - 1))
  done
  printf '%s' "$value" | tr '_-' '/+' | base64 -d 2>/dev/null
}

# Given — ensure unique seller email is absent
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null

# When — register seller and extract returned JWT token
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SecurePass123!\",\"role\":\"SELLER\",\"storeName\":\"Token Test Shop\"}")"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
PAYLOAD_SEGMENT="$(printf '%s' "$TOKEN" | cut -d '.' -f 2)"
b64url_decode "$PAYLOAD_SEGMENT" > "$PAYLOAD_FILE"

# Then — response is 201 and decoded JWT payload matches response claims
[ "$HTTP_STATUS" = "201" ]
grep -F "\"id\":\"${USER_ID}\"" "$PAYLOAD_FILE" >/dev/null
grep -F "\"email\":\"${EMAIL}\"" "$PAYLOAD_FILE" >/dev/null
grep -F '"role":"SELLER"' "$PAYLOAD_FILE" >/dev/null
grep -F '"status":"PENDING"' "$PAYLOAD_FILE" >/dev/null
grep -F "\"sellerProfileId\":\"${SELLER_PROFILE_ID}\"" "$PAYLOAD_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:register_token_contains_correct_claims"

# Cleanup — remove created rows
