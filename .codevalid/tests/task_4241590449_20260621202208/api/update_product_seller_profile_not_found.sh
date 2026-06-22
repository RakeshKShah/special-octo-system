#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/update_product_seller_profile_not_found_${CASE_SUFFIX}.json"
TOKEN="${SELLER_NO_PROFILE_TOKEN:-}"

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — use a valid ACTIVE SELLER token whose backing user has no seller profile row
[ -n "$TOKEN" ]

# When — seller without profile attempts product update
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-666-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data '{"title":"Test Product"}')"

# Then — response is 404 Seller profile not found
[ "$HTTP_STATUS" = "404" ]
grep -F '"error":"Seller profile not found"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_seller_profile_not_found'

# Cleanup — remove temporary files
