#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-missing-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_not_found_wrong_id_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_not_found_wrong_id_${CASE_SUFFIX}.json"
TOKEN=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register an ACTIVE seller and choose a product id that does not exist
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN" ]

# When — update a non-existent product id
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-nonexistent-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Test Product"}')"

# Then — response is 404 Product not found
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_not_found_wrong_id'

# Cleanup — remove temporary files
