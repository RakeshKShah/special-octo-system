#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
REGISTER_RESPONSE_FILE="$(mktemp)"
ORDER_ID="nonexistent-order-${CASE_SUFFIX}"
SELLER_EMAIL="seller-missing-${CASE_SUFFIX}@example.com"
SELLER_TOKEN=""
SELLER_USER_ID=""
cleanup() {
  [ -n "$SELLER_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$SELLER_USER_ID'" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$REGISTER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL\",\"password\":\"Password123!\",\"role\":\"SELLER\",store_name:\"Store $CASE_SUFFIX\",\"bio\":\"Bio $CASE_SUFFIX\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '$SELLER_USER_ID'" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $SELLER_TOKEN" "$BASE_URL/orders/$ORDER_ID/ship")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ]
grep -F 'Order not found' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:nonexistent_order_returns_404'
