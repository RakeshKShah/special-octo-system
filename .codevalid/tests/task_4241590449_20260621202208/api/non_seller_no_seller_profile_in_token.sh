#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-token-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/non_seller_no_seller_profile_in_token_${CASE_SUFFIX}.json"
PAYLOAD_FILE="/tmp/non_seller_no_seller_profile_in_token_payload_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

# Given — ensure unique buyer email and DB connectivity
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true

# When — register buyer and decode JWT payload
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"BuyerPass123!\",\"role\":\"BUYER\"}")"
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f 2)"
PAYLOAD_B64_PADDED="$(printf '%s' "$PAYLOAD_B64" | awk '{ l=length($0)%4; if (l==2) printf "%s==", $0; else if (l==3) printf "%s=", $0; else if (l==1) printf "%s===", $0; else printf "%s", $0; }')"
printf '%s' "$PAYLOAD_B64_PADDED" | tr '_-' '/+' | base64 -d > "$PAYLOAD_FILE"

# Then — assert sellerProfileId absent or null for non-seller token
[ "$HTTP_STATUS" = "201" ]
[ -n "$TOKEN" ]
if jq -e 'has("sellerProfileId")' "$PAYLOAD_FILE" >/dev/null; then
  jq -e '.sellerProfileId == null' "$PAYLOAD_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_no_seller_profile_in_token"

# Cleanup — handled by trap
