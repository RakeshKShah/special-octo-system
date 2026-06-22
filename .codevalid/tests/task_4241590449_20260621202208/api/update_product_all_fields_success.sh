#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-all-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_all_fields_success_register_${CASE_SUFFIX}.json"
CREATE_FILE="/tmp/update_product_all_fields_success_create_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_all_fields_success_${CASE_SUFFIX}.json"
TOKEN=""
PRODUCT_ID=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$CREATE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a seller and create a product owned by that seller
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Shop ${CASE_SUFFIX}\",\"bio\":\"Initial bio\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN" ]

CREATE_STATUS="$(curl -sS -o "$CREATE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data "{\"title\":\"Original ${CASE_SUFFIX}\",\"description\":\"Original desc\",\"category\":\"HOME_GOODS\",\"price_cents\":1999,\"stock_qty\":8,\"photos\":[\"https://cdn.example.com/original-${CASE_SUFFIX}.jpg\"]}")"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID="$(grep -o '"id":"[^"]*"' "$CREATE_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID" ]

# When — update all mutable product fields
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Handcrafted Ceramic Mug","description":"Beautiful handmade mug","category":"HOME_GOODS","price_cents":2999,"stock_qty":15,"photos":["https://cdn.example.com/mug1.jpg","https://cdn.example.com/mug2.jpg"]}')"

# Then — response is 200 and body reflects all updated fields
[ "$HTTP_STATUS" = "200" ]
grep -F '"title":"Handcrafted Ceramic Mug"' "$RESPONSE_FILE" >/dev/null
grep -F '"description":"Beautiful handmade mug"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"HOME_GOODS"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":2999' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":15' "$RESPONSE_FILE" >/dev/null
grep -F 'https://cdn.example.com/mug1.jpg' "$RESPONSE_FILE" >/dev/null
grep -F 'https://cdn.example.com/mug2.jpg' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_all_fields_success'

# Cleanup — remove temporary files only; no public delete endpoint available in provided API surface
