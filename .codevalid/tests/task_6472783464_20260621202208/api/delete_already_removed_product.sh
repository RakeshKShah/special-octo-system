#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-105}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated seller and a product fixture already marked removed
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller deletes the already removed product
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — current implementation may succeed as idempotent no-op or return not found
case "$HTTP_CODE" in
  200)
    grep -F 'success' "$RESPONSE_FILE" >/dev/null || { echo "Expected success body for 200 response"; cat "$RESPONSE_FILE"; exit 1; }
    ;;
  404)
    grep -F 'Product not found' "$RESPONSE_FILE" >/dev/null || { echo "Expected product not found body for 404 response"; cat "$RESPONSE_FILE"; exit 1; }
    ;;
  *)
    echo "Expected 200 or 404 got $HTTP_CODE"
    cat "$RESPONSE_FILE"
    exit 1
    ;;
esac

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:delete_already_removed_product'
