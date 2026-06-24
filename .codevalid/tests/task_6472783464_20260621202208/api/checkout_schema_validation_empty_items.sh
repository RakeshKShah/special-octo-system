#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-${AUTH_HEADER:-Authorization: Bearer buyer-token}}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
# Authenticated buyer request with invalid empty items payload.

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d '{"items":[]}' "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "400" ]
grep -Eq 'error|message|issues' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_schema_validation_empty_items'
