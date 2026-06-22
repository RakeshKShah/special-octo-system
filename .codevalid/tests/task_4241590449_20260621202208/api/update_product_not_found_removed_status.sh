#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/update_product_not_found_removed_status_${CASE_SUFFIX}.json"
TOKEN="${ACTIVE_SELLER_TOKEN_WITH_REMOVED_PRODUCT:-}"
PRODUCT_ID="${REMOVED_PRODUCT_ID:-}"

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — use an ACTIVE seller token and a product id already in REMOVED status supplied by environment
[ -n "$TOKEN" ]
[ -n "$PRODUCT_ID" ]

# When — attempt to update removed product
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/$PRODUCT_ID" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Attempt to Restore"}')"

# Then — response is 404 Product not found
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Product not found"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_not_found_removed_status'

# Cleanup — remove temporary files
