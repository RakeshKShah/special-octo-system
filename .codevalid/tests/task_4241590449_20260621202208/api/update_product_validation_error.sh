#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-validation-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_validation_error_register_${CASE_SUFFIX}.json"
CREATE_FILE="/tmp/update_product_validation_error_create_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_validation_error_${CASE_SUFFIX}.json"
TOKEN=""
PRODUCT_ID=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$CREATE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a seller and create a valid product
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN" ]

CREATE_STATUS="$(curl -sS -o "$CREATE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Valid Product","description":"Valid","category":"HOME_GOODS","price_cents":900,"stock_qty":2,"photos":["https://cdn.example.com/valid.jpg"]}')"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID="$(grep -o '"id":"[^"]*"' "$CREATE_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID" ]

# When — submit invalid product schema data
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"price_cents":-100,"stock_qty":"invalid"}')"

# Then — response is 400 with a validation error message
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_validation_error'

# Cleanup — remove temporary files
