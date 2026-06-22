#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-photos-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_photos_success_register_${CASE_SUFFIX}.json"
CREATE_FILE="/tmp/update_product_photos_success_create_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_photos_success_${CASE_SUFFIX}.json"
TOKEN=""
PRODUCT_ID=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$CREATE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a seller and create a product with initial photos
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
  --data '{"title":"Photo Product","description":"Old photo","category":"HOME_GOODS","price_cents":1700,"stock_qty":6,"photos":["old-photo.jpg"]}')"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID="$(grep -o '"id":"[^"]*"' "$CREATE_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID" ]

# When — replace the photos array
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"photos":["https://cdn.example.com/new-photo1.jpg","https://cdn.example.com/new-photo2.jpg","https://cdn.example.com/new-photo3.jpg"]}')"

# Then — response is 200 and contains the new photo URLs
[ "$HTTP_STATUS" = "200" ]
grep -F 'https://cdn.example.com/new-photo1.jpg' "$RESPONSE_FILE" >/dev/null
grep -F 'https://cdn.example.com/new-photo2.jpg' "$RESPONSE_FILE" >/dev/null
grep -F 'https://cdn.example.com/new-photo3.jpg' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_photos_success'

# Cleanup — remove temporary files
