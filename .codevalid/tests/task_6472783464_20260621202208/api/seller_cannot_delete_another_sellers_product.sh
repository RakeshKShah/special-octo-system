#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-108}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated seller and a product owned by another seller
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller tries to delete another seller's product
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — scoped lookup fails with not found
[ "$HTTP_CODE" = "404" ] || { echo "Expected 404 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -F 'Product not found' "$RESPONSE_FILE" >/dev/null || { echo "Expected product not found message"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:seller_cannot_delete_another_sellers_product'
