#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="seller-token-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"
PAYLOAD_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register a seller and capture the issued token
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"SellerPass123!\",\"role\":\"SELLER\",\"storeName\":\"Token Shop\",\"bio\":\"Testing token\"}" "$BASE_URL/auth/register")

# Then — assert token payload contains matching sellerProfileId
[ "$HTTP_CODE" = "201" ]
grep -F '"token"' "$RESPONSE_FILE" >/dev/null
TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$RESPONSE_FILE")
SELLER_PROFILE_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["user"]["sellerProfile"]["id"])' "$RESPONSE_FILE")
[ -n "$TOKEN" ]
[ -n "$SELLER_PROFILE_ID" ]
TOKEN_PAYLOAD_B64=$(printf '%s' "$TOKEN" | cut -d '.' -f 2)
python3 -c 'import base64,sys; payload=sys.argv[1]; payload += "=" * (-len(payload) % 4); sys.stdout.write(base64.urlsafe_b64decode(payload.encode()).decode())' "$TOKEN_PAYLOAD_B64" > "$PAYLOAD_FILE"
grep -F '"sellerProfileId":"'"$SELLER_PROFILE_ID"'"' "$PAYLOAD_FILE" >/dev/null

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:seller_profile_reflection_in_token'
