#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
UPDATE_RESPONSE_FILE="$(mktemp)"
NONEXISTENT_PRODUCT_ID="prod-unauth-${CASE_SUFFIX}"

cleanup() {
  rm -f "$UPDATE_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$UPDATE_RESPONSE_FILE" -w '%{http_code}' -X PUT -H 'Content-Type: application/json' -d "{\"title\":\"Unauthorized Update\"}" "$BASE_URL/products/$NONEXISTENT_PRODUCT_ID")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "401" ] || { echo "expected 401 got $HTTP_CODE"; cat "$UPDATE_RESPONSE_FILE"; exit 1; }

# Cleanup — undo Given side effects

printf '%s\n' 'CODEVALID_TEST_ASSERTION_OK:update_product_unauthenticated'
