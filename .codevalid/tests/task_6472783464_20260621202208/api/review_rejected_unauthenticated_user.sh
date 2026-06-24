#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
RESPONSE_FILE="$(mktemp)"
MISSING_ORDER_ITEM_ID="orderitem-$(date +%s)-$$"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
# Stateless setup only.

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"order_item_id\":\"$MISSING_ORDER_ITEM_ID\",\"rating\":4,\"body\":\"Unauthorized review\"}" "$BASE_URL/reviews")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "401" ]

# Cleanup — no stateful setup to undo

echo 'CODEVALID_TEST_ASSERTION_OK:review_rejected_unauthenticated_user'
