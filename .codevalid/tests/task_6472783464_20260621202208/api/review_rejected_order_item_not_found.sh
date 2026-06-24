#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-${CASE_SUFFIX}"
MISSING_ORDER_ITEM_ID="nonexistent-item-$CASE_SUFFIX"
RESPONSE_FILE="$(mktemp)"
LOGIN_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$LOGIN_FILE"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$BUYER_ID';" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role) VALUES ('$BUYER_ID', 'buyer-$CASE_SUFFIX@example.com', 'password123', 'BUYER');" >/dev/null
HTTP_CODE=$(curl -sS -o "$LOGIN_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"buyer-$CASE_SUFFIX@example.com\",\"password\":\"password123\"}" "$BASE_URL/auth/login")
[ "$HTTP_CODE" = "200" ]
TOKEN=$(jq -r '.token // .accessToken // .jwt // empty' "$LOGIN_FILE")
[ -n "$TOKEN" ]

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"order_item_id\":\"$MISSING_ORDER_ITEM_ID\",\"rating\":3,\"body\":\"Test review\"}" "$BASE_URL/reviews")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ]
grep -F 'Order item not found' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# handled by trap

echo 'CODEVALID_TEST_ASSERTION_OK:review_rejected_order_item_not_found'
