#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-token-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_profile_reflection_in_token_${CASE_SUFFIX}.json"
PAYLOAD_FILE="/tmp/seller_profile_reflection_in_token_payload_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

# Given — ensure unique seller email and DB connectivity
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true

# When — register seller and decode JWT payload
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Token Shop\",\"bio\":\"Testing token\"}")"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
USER_SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f 2)"
PAYLOAD_B64_PADDED="$(printf '%s' "$PAYLOAD_B64" | awk '{ l=length($0)%4; if (l==2) printf "%s==", $0; else if (l==3) printf "%s=", $0; else if (l==1) printf "%s===", $0; else printf "%s", $0; }')"
printf '%s' "$PAYLOAD_B64_PADDED" | tr '_-' '/+' | base64 -d > "$PAYLOAD_FILE"

# Then — assert sellerProfileId claim matches response seller profile id
[ "$HTTP_STATUS" = "201" ]
[ -n "$TOKEN" ]
[ "$USER_SELLER_PROFILE_ID" != "null" ]
jq -e --arg spid "$USER_SELLER_PROFILE_ID" '.sellerProfileId == $spid' "$PAYLOAD_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_profile_reflection_in_token"

# Cleanup — handled by trap
