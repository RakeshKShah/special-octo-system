#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-partial-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_partial_fields_success_register_${CASE_SUFFIX}.json"
CREATE_FILE="/tmp/update_product_partial_fields_success_create_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_partial_fields_success_${CASE_SUFFIX}.json"
TOKEN=""
PRODUCT_ID=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$CREATE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a seller and create a baseline product
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
  --data '{"title":"Original Title","description":"Baseline","category":"HOME_GOODS","price_cents":1500,"stock_qty":10,"photos":["https://cdn.example.com/original-photo.jpg"]}')"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID="$(grep -o '"id":"[^"]*"' "$CREATE_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID" ]

# When — update only selected fields
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Updated Title","stock_qty":25}')"

# Then — response is 200, changed fields updated, unchanged fields preserved
[ "$HTTP_STATUS" = "200" ]
grep -F '"title":"Updated Title"' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":25' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":1500' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_partial_fields_success'

# Cleanup — remove temporary files only; no public delete endpoint available in provided API surface
