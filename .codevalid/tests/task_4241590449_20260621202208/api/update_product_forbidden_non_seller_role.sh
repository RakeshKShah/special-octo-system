#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
PASSWORD='Password123!'
REGISTER_FILE="/tmp/update_product_forbidden_non_seller_role_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/update_product_forbidden_non_seller_role_${CASE_SUFFIX}.json"
TOKEN=""

cleanup_files() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register an ACTIVE BUYER user
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"BUYER\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -n1 | cut -d '"' -f4)"
[ -n "$TOKEN" ]

# When — buyer attempts to update a product
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-444-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Test Product"}')"

# Then — response is 403 Seller access required
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_forbidden_non_seller_role'

# Cleanup — remove temporary files
