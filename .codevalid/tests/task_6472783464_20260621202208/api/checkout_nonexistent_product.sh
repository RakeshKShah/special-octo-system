#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-${AUTH_HEADER:-Authorization: Bearer buyer-token}}"

CASE_SUFFIX="$(date +%s)-$$"
PRODUCT_ID="prod-nonexistent-${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
# No product is created for this unique id.

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d "{\"items\":[{\"product_id\":\"$PRODUCT_ID\",\"qty\":1}]}" "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "400" ]
grep -F "Product $PRODUCT_ID unavailable" "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_nonexistent_product'
