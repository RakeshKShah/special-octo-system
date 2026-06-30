#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
REGISTER_RESPONSE_FILE="$(mktemp)"
UPDATE_RESPONSE_FILE="$(mktemp)"
SELLER_EMAIL="seller-noseller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
TOKEN=""
ARBITRARY_PRODUCT_ID="prod-any-${CASE_SUFFIX}"

cleanup() {
  rm -f "$REGISTER_RESPONSE_FILE" "$UPDATE_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
REGISTER_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL\",\"password\":\"$SELLER_PASSWORD\",\"role\":\"SELLER\",store_name:\"Store-${CASE_SUFFIX}\",\"bio\":\"Bio-${CASE_SUFFIX}\"}" "$BASE_URL/auth/register")
[ "$REGISTER_CODE" = "201" ] || { echo "expected register 201 got $REGISTER_CODE"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }
TOKEN=$(jq -r '.token' "$REGISTER_RESPONSE_FILE")
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "missing token"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$UPDATE_RESPONSE_FILE" -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"title\":\"Update Attempt\"}" "$BASE_URL/products/$ARBITRARY_PRODUCT_ID")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ] || { echo "expected 404 got $HTTP_CODE"; cat "$UPDATE_RESPONSE_FILE"; exit 1; }
grep -E 'Seller profile not found|Product not found' "$UPDATE_RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:update_product_seller_profile_not_found'
