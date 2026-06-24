#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-${AUTH_HEADER:-Authorization: Bearer buyer-token}}"
RESPONSE_FILE="$(mktemp)"
SECOND_RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE" "$SECOND_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
# Authenticated buyer request with malformed payloads.

# When — perform the action under test
HTTP_CODE_ONE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d '{"items":[{"product_id":"prod-123"}]}' "$BASE_URL/checkout")
HTTP_CODE_TWO=$(curl -sS -o "$SECOND_RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d '{"items":[{"qty":2}]}' "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE_ONE" = "400" ]
[ "$HTTP_CODE_TWO" = "400" ]
grep -Eq 'error|message|issues' "$RESPONSE_FILE" >/dev/null
grep -Eq 'error|message|issues' "$SECOND_RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_schema_validation_missing_fields'
