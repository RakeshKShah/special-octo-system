#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_NO_PROFILE_TOKEN="${SELLER_NO_PROFILE_TOKEN:-seller-99-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-104}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated identity whose seller profile lookup will not resolve
AUTH_HEADER="Authorization: Bearer $SELLER_NO_PROFILE_TOKEN"

# When — delete is requested
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — handler reports missing seller profile
[ "$HTTP_CODE" = "404" ] || { echo "Expected 404 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -F 'Seller profile not found' "$RESPONSE_FILE" >/dev/null || { echo "Expected seller profile not found message"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:delete_product_seller_profile_not_found'
