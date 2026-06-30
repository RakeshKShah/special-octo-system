#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="inactive-seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
REGISTER_RESPONSE_FILE="/tmp/inactive_seller_forbidden_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/inactive_seller_forbidden_response_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$REGISTER_RESPONSE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a unique seller account; implementation issues PENDING seller status on registration.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",store_name:\"Inactive ${CASE_SUFFIX}\",\"bio\":\"bio-${CASE_SUFFIX}\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
[ "$TOKEN" != "null" ]
[ -n "$TOKEN" ]

# When — attempt to ship an order while not ACTIVE.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/order-${CASE_SUFFIX}/ship" \
  -H "Authorization: Bearer $TOKEN")"

# Then — request is forbidden for non-active seller state.
[ "$HTTP_STATUS" = "403" ]
jq -e '.error == "Active seller required"' "$RESPONSE_FILE" >/dev/null

# Cleanup — no cleanup API exposed for registered users.
echo "CODEVALID_TEST_ASSERTION_OK:inactive_seller_forbidden"
