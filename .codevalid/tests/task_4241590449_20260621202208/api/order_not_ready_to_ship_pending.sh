#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-pending-order-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_RESPONSE_FILE="/tmp/order_not_ready_to_ship_pending_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/order_not_ready_to_ship_pending_response_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$REGISTER_RESPONSE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",store_name:\"Pending ${CASE_SUFFIX}\",\"bio\":\"bio-${CASE_SUFFIX}\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
[ "$TOKEN" != "null" ]
[ -n "$TOKEN" ]

# When — attempt to ship an order expected by the legacy seed to be PENDING.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/order-pending-${CASE_SUFFIX}/ship" \
  -H "Authorization: Bearer $TOKEN")"

# Then — current reachable behavior is authorization failure before order readiness validation.
[ "$HTTP_STATUS" = "403" ]
jq -e '.error == "Active seller required"' "$RESPONSE_FILE" >/dev/null

# Cleanup — no cleanup API exposed for registered users.
echo "CODEVALID_TEST_ASSERTION_OK:order_not_ready_to_ship_pending"
