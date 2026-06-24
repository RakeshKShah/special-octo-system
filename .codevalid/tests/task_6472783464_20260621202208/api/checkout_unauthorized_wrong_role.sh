#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_AUTH_HEADER="${SELLER_AUTH_HEADER:-Authorization: Bearer seller-token}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
# Authenticated non-BUYER user represented by SELLER_AUTH_HEADER.

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$SELLER_AUTH_HEADER" -H 'Content-Type: application/json' -d '{"items":[{"product_id":"prod-456","qty":1}]}' "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "403" ]

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_unauthorized_wrong_role'
