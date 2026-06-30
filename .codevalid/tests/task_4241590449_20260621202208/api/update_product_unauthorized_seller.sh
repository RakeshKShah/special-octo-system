#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
REGISTER_RESPONSE_FILE_1="$(mktemp)"
REGISTER_RESPONSE_FILE_2="$(mktemp)"
CREATE_RESPONSE_FILE="$(mktemp)"
UPDATE_RESPONSE_FILE="$(mktemp)"
SELLER_EMAIL_1="seller-a-${CASE_SUFFIX}@example.com"
SELLER_EMAIL_2="seller-b-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
TOKEN_1=""
TOKEN_2=""
PRODUCT_ID=""

cleanup() {
  rm -f "$REGISTER_RESPONSE_FILE_1" "$REGISTER_RESPONSE_FILE_2" "$CREATE_RESPONSE_FILE" "$UPDATE_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
REGISTER_CODE_1=$(curl -sS -o "$REGISTER_RESPONSE_FILE_1" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL_1\",\"password\":\"$SELLER_PASSWORD\",\"role\":\"SELLER\",store_name:\"Store-A-${CASE_SUFFIX}\",\"bio\":\"Bio-A-${CASE_SUFFIX}\"}" "$BASE_URL/auth/register")
[ "$REGISTER_CODE_1" = "201" ] || { echo "expected register 1 201 got $REGISTER_CODE_1"; cat "$REGISTER_RESPONSE_FILE_1"; exit 1; }
TOKEN_1=$(jq -r '.token' "$REGISTER_RESPONSE_FILE_1")
[ -n "$TOKEN_1" ] && [ "$TOKEN_1" != "null" ] || { echo "missing token 1"; cat "$REGISTER_RESPONSE_FILE_1"; exit 1; }
REGISTER_CODE_2=$(curl -sS -o "$REGISTER_RESPONSE_FILE_2" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL_2\",\"password\":\"$SELLER_PASSWORD\",\"role\":\"SELLER\",store_name:\"Store-B-${CASE_SUFFIX}\",\"bio\":\"Bio-B-${CASE_SUFFIX}\"}" "$BASE_URL/auth/register")
[ "$REGISTER_CODE_2" = "201" ] || { echo "expected register 2 201 got $REGISTER_CODE_2"; cat "$REGISTER_RESPONSE_FILE_2"; exit 1; }
TOKEN_2=$(jq -r '.token' "$REGISTER_RESPONSE_FILE_2")
[ -n "$TOKEN_2" ] && [ "$TOKEN_2" != "null" ] || { echo "missing token 2"; cat "$REGISTER_RESPONSE_FILE_2"; exit 1; }
CREATE_CODE=$(curl -sS -o "$CREATE_RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN_2" -H 'Content-Type: application/json' -d "{\"title\":\"Other Seller Product ${CASE_SUFFIX}\",\"description\":\"Original description\",\"category\":\"tools\",\"price_cents\":1999,\"stock_qty\":10,\"photos\":[\"https://example.com/original-${CASE_SUFFIX}.jpg\"]}" "$BASE_URL/products")
[ "$CREATE_CODE" = "201" ] || { echo "expected create 201 got $CREATE_CODE"; cat "$CREATE_RESPONSE_FILE"; exit 1; }
PRODUCT_ID=$(jq -r '.id' "$CREATE_RESPONSE_FILE")
[ -n "$PRODUCT_ID" ] && [ "$PRODUCT_ID" != "null" ] || { echo "missing product id"; cat "$CREATE_RESPONSE_FILE"; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$UPDATE_RESPONSE_FILE" -w '%{http_code}' -X PUT -H "Authorization: Bearer $TOKEN_1" -H 'Content-Type: application/json' -d "{\"title\":\"Attempted Update\"}" "$BASE_URL/products/$PRODUCT_ID")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ] || { echo "expected 404 got $HTTP_CODE"; cat "$UPDATE_RESPONSE_FILE"; exit 1; }
grep -F 'Product not found' "$UPDATE_RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:update_product_unauthorized_seller'
