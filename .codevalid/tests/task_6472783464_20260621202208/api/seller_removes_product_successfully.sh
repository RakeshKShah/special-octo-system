#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-101}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — authenticated active seller and an owned product exist in the environment fixtures
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller deletes their own product
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — soft-delete request succeeds
[ "$HTTP_CODE" = "200" ] || { echo "Expected 200 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -F 'success' "$RESPONSE_FILE" >/dev/null || { echo "Expected success field"; cat "$RESPONSE_FILE"; exit 1; }
grep -F 'true' "$RESPONSE_FILE" >/dev/null || { echo "Expected success=true"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none; script does not create fixture data directly

echo 'CODEVALID_TEST_ASSERTION_OK:seller_removes_product_successfully'
