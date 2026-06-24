#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_TOKEN="${BUYER_TOKEN:-buyer-7-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-103}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated user without active seller privileges
AUTH_HEADER="Authorization: Bearer $BUYER_TOKEN"

# When — non-seller attempts to delete a product
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — seller authorization fails
[ "$HTTP_CODE" = "403" ] || { echo "Expected 403 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -E 'error|seller|active|forbidden' "$RESPONSE_FILE" >/dev/null || { echo "Expected active seller error payload"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:delete_product_non_seller_user'
