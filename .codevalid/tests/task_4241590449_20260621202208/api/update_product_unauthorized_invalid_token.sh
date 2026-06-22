#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/update_product_unauthorized_invalid_token_${CASE_SUFFIX}.json"
INVALID_TOKEN='invalid.token.here'

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — a malformed bearer token
: "$INVALID_TOKEN"

# When — send update request with invalid JWT
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X PUT "$BASE_URL/products/prod-333-${CASE_SUFFIX}" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $INVALID_TOKEN" \
  --data '{"title":"Test Product"}')"

# Then — response is 401 Invalid token
[ "$HTTP_STATUS" = "401" ]
grep -F '"error":"Invalid token"' "$RESPONSE_FILE" >/dev/null

echo 'CODEVALID_TEST_ASSERTION_OK:update_product_unauthorized_invalid_token'

# Cleanup — remove temporary files
