#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-999}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated seller and a product id outside that seller's scope
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller attempts deletion of missing or unowned product
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — handler returns product not found
[ "$HTTP_CODE" = "404" ] || { echo "Expected 404 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -F 'Product not found' "$RESPONSE_FILE" >/dev/null || { echo "Expected product not found message"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:delete_product_not_found_or_not_owned'
