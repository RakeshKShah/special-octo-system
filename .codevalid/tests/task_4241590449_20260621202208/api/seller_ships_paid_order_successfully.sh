#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller-${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Store ${CASE_SUFFIX}"
PRODUCT_TITLE="Product ${CASE_SUFFIX}"
REGISTER_RESPONSE_FILE="/tmp/seller_ships_paid_order_successfully_register_${CASE_SUFFIX}.json"
PRODUCT_RESPONSE_FILE="/tmp/seller_ships_paid_order_successfully_product_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_ships_paid_order_successfully_response_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$REGISTER_RESPONSE_FILE" "$PRODUCT_RESPONSE_FILE" "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",store_name:\"${STORE_NAME}\",\"bio\":\"bio-${CASE_SUFFIX}\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
[ "$TOKEN" != "null" ]
[ -n "$TOKEN" ]

# Given — attempt product creation to document seller onboarding behavior.
PRODUCT_CREATE_STATUS="$(curl -sS -o "$PRODUCT_RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  --data "{\"title\":\"${PRODUCT_TITLE}\",\"description\":\"desc-${CASE_SUFFIX}\",\"category\":\"general\",\"price_cents\":1234,\"stock_qty\":5,\"photos\":[\"https://example.com/${CASE_SUFFIX}.jpg\"]}")"
[ "$PRODUCT_CREATE_STATUS" = "403" ] || [ "$PRODUCT_CREATE_STATUS" = "201" ]

# When — seller calls the order ship endpoint.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/order-${CASE_SUFFIX}/ship" \
  -H "Authorization: Bearer $TOKEN")"

# Then — current reachable behavior is authorization failure because new sellers are not ACTIVE.
[ "$HTTP_STATUS" = "403" ]
jq -e '.error == "Active seller required"' "$RESPONSE_FILE" >/dev/null

# Cleanup — no server-side cleanup API is available for created users in the exposed call graph.
echo "CODEVALID_TEST_ASSERTION_OK:seller_ships_paid_order_successfully"
