#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL_A="seller-a-${CASE_SUFFIX}@example.com"
EMAIL_B="seller-b-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_A_FILE="/tmp/update_product_not_found_other_seller_register_a_${CASE_SUFFIX}.json"
REGISTER_B_FILE="/tmp/update_product_not_found_other_seller_register_b_${CASE_SUFFIX}.json"
CREATE_B_FILE="/tmp/update_product_not_found_other_seller_create_b_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_not_found_other_seller_${CASE_SUFFIX}.json"
TOKEN_A=""
TOKEN_B=""
PRODUCT_ID_B=""

cleanup_files() {
  rm -f "$REGISTER_A_FILE" "$REGISTER_B_FILE" "$CREATE_B_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register seller A and seller B, then create seller B's product
STATUS_A="$(curl -sS -o "$REGISTER_A_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL_A}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}")"
[ "$STATUS_A" = "201" ]
TOKEN_A="$(grep -o '"token":"[^"]*"' "$REGISTER_A_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN_A" ]

STATUS_B="$(curl -sS -o "$REGISTER_B_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL_B}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}")"
[ "$STATUS_B" = "201" ]
TOKEN_B="$(grep -o '"token":"[^"]*"' "$REGISTER_B_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN_B" ]

CREATE_STATUS="$(curl -sS -o "$CREATE_B_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN_B" \
  --data '{"title":"Owned by B","description":"Private","category":"HOME_GOODS","price_cents":1234,"stock_qty":4,"photos":["https://cdn.example.com/b.jpg"]}')"
[ "$CREATE_STATUS" = "201" ]
PRODUCT_ID_B="$(grep -o '"id":"[^"]*"' "$CREATE_B_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$PRODUCT_ID_B" ]

# When — seller A attempts to update seller B's product
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID_B" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN_A" \
  --data '{"title":"Hijacked Product"}')"

# Then — response is 404 Product not found
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_not_found_other_seller'

# Cleanup — remove temporary files
