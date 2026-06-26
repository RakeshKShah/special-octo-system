#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TEST_EMAIL="buyer-token-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="$(mktemp)"
PAYLOAD_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE" "$PAYLOAD_FILE"
}
trap cleanup EXIT

# Given — no pre-existing user for the generated email

# When — register a buyer and capture the issued token
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"BuyerPass123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")

# Then — assert sellerProfileId is absent or null in the buyer token payload
[ "$HTTP_CODE" = "201" ]
grep -F '"token"' "$RESPONSE_FILE" >/dev/null
TOKEN=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["token"])' "$RESPONSE_FILE")
[ -n "$TOKEN" ]
TOKEN_PAYLOAD_B64=$(printf '%s' "$TOKEN" | cut -d '.' -f 2)
python3 -c 'import base64,sys; payload=sys.argv[1]; payload += "=" * (-len(payload) % 4); sys.stdout.write(base64.urlsafe_b64decode(payload.encode()).decode())' "$TOKEN_PAYLOAD_B64" > "$PAYLOAD_FILE"
if grep -F '"sellerProfileId"' "$PAYLOAD_FILE" >/dev/null; then grep -F '"sellerProfileId":null' "$PAYLOAD_FILE" >/dev/null; fi

# Cleanup — no reversible public cleanup endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:non_seller_no_seller_profile_in_token'
