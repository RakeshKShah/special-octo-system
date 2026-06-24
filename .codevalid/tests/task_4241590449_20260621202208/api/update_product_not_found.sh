#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
REGISTER_RESPONSE_FILE="$(mktemp)"
UPDATE_RESPONSE_FILE="$(mktemp)"
SELLER_EMAIL="seller-not-found-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
TOKEN=""
MISSING_PRODUCT_ID="prod-nonexistent-${CASE_SUFFIX}"

cleanup() {
  rm -f "$REGISTER_RESPONSE_FILE" "$UPDATE_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
REGISTER_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL\",\"password\":\"$SELLER_PASSWORD\",\"role\":\"SELLER\",\"storeName\":\"Store-${CASE_SUFFIX}\",\"bio\":\"Bio-${CASE_SUFFIX}\"}" "$BASE_URL/register")
[ "$REGISTER_CODE" = "201" ] || { echo "expected register 201 got $REGISTER_CODE"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }
TOKEN=$(jq -r '.token' "$REGISTER_RESPONSE_FILE")
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "missing token"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$UPDATE_RESPONSE_FILE" -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"title\":\"Updated Title\"}" "$BASE_URL/products/$MISSING_PRODUCT_ID")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ] || { echo "expected 404 got $HTTP_CODE"; cat "$UPDATE_RESPONSE_FILE"; exit 1; }
grep -F 'Product not found' "$UPDATE_RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:update_product_not_found'
