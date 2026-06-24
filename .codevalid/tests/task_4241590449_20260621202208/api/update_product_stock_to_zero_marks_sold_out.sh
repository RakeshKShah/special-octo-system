#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
REGISTER_RESPONSE_FILE="$(mktemp)"
CREATE_RESPONSE_FILE="$(mktemp)"
UPDATE_RESPONSE_FILE="$(mktemp)"
SELLER_EMAIL="seller-zero-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
TOKEN=""
PRODUCT_ID=""

cleanup() {
  rm -f "$REGISTER_RESPONSE_FILE" "$CREATE_RESPONSE_FILE" "$UPDATE_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
REGISTER_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL\",\"password\":\"$SELLER_PASSWORD\",\"role\":\"SELLER\",\"storeName\":\"Store-${CASE_SUFFIX}\",\"bio\":\"Bio-${CASE_SUFFIX}\"}" "$BASE_URL/register")
[ "$REGISTER_CODE" = "201" ] || { echo "expected register 201 got $REGISTER_CODE"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }
TOKEN=$(jq -r '.token' "$REGISTER_RESPONSE_FILE")
[ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "missing token"; cat "$REGISTER_RESPONSE_FILE"; exit 1; }
CREATE_CODE=$(curl -sS -o "$CREATE_RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"title\":\"Stocked Product ${CASE_SUFFIX}\",\"description\":\"Original description\",\"category\":\"tools\",\"price_cents\":1999,\"stock_qty\":10,\"photos\":[\"https://example.com/original-${CASE_SUFFIX}.jpg\"]}" "$BASE_URL/products")
[ "$CREATE_CODE" = "201" ] || { echo "expected create 201 got $CREATE_CODE"; cat "$CREATE_RESPONSE_FILE"; exit 1; }
PRODUCT_ID=$(jq -r '.id' "$CREATE_RESPONSE_FILE")
[ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "null" ] || { echo "missing product id"; cat "$CREATE_RESPONSE_FILE"; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$UPDATE_RESPONSE_FILE" -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"stock_qty\":0}" "$BASE_URL/products/$PRODUCT_ID")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ] || { echo "expected 200 got $HTTP_CODE"; cat "$UPDATE_RESPONSE_FILE"; exit 1; }
grep -F '0' "$UPDATE_RESPONSE_FILE" >/dev/null
grep -F 'SOLD_OUT' "$UPDATE_RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:update_product_stock_to_zero_marks_sold_out'
