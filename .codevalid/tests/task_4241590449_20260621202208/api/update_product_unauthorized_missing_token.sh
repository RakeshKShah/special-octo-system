#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/update_product_unauthorized_missing_token_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — no Authorization header is provided
: "stateless precondition"

# When — send unauthenticated update request
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-222-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Test Product"}')"

# Then — response is 401 Unauthorized
[ "$HTTP_STATUS" = "401" ]
grep -F '"error":"Unauthorized"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_unauthorized_missing_token'

# Cleanup — remove temporary files
