#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-oos-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/mark_product_out_of_stock_register_${CASE_SUFFIX}.json"
CREATE_FILE="/tmp/mark_product_out_of_stock_create_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/mark_product_out_of_stock_${CASE_SUFFIX}.json"
TOKEN=""
PRODUCT_ID=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$CREATE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a seller and create an in-stock product
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
  --data '{"title":"Stocked Product","description":"Before zero","category":"HOME_GOODS","price_cents":2200,"stock_qty":5,"photos":["https://cdn.example.com/stocked.jpg"]}')"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID="$(grep -o '"id":"[^"]*"' "$CREATE_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID" ]

# When — set stock quantity to zero
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"stock_qty":0}')"

# Then — response is 200 and stock quantity is zero
[ "$HTTP_STATUS" = "200" ]
grep -F '"stockQty":0' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:mark_product_out_of_stock'

# Cleanup — remove temporary files only; no public delete endpoint available in provided API surface
