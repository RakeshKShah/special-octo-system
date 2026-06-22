#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/update_product_forbidden_inactive_seller_${CASE_SUFFIX}.json"
TOKEN="${SUSPENDED_SELLER_TOKEN:-}"

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — use a valid SELLER token for a non-ACTIVE seller supplied by environment
[ -n "$TOKEN" ]

# When — inactive seller attempts product update
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-555-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Test Product"}')"

# Then — response is 403 Seller account must be active
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Seller account must be active"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_forbidden_inactive_seller'

# Cleanup — remove temporary files
