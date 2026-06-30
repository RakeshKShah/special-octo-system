#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
REGISTER_RESPONSE_FILE="$(mktemp)"
ORDER_ID="order-unauth-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-unauth-${CASE_SUFFIX}@example.com"
BUYER_USER_ID=""
cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM orders WHERE id = '$ORDER_ID'" >/dev/null 2>&1 || true
  [ -n "$BUYER_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$BUYER_USER_ID'" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$REGISTER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$BUYER_EMAIL\",\"password\":\"Password123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
BUYER_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO orders (id, buyer_id, status, created_at) VALUES ('$ORDER_ID', '$BUYER_USER_ID', 'PAID', NOW())" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST "$BASE_URL/orders/$ORDER_ID/ship")

# Then — HTTP/body assertions
if [ "$HTTP_CODE" != "401" ] && [ "$HTTP_CODE" != "403" ]; then echo "Expected 401 or 403 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:unauthenticated_user_blocked'
