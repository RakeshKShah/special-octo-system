#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="pending-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!Aa"
STORE_NAME="Pending-Store-${CASE_SUFFIX}"
BIO="Pending-Bio-${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"
REGISTER_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"SELLER\",\"storeName\":\"$STORE_NAME\",\"bio\":\"$BIO\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"Pending Product ${CASE_SUFFIX}\",\"description\":\"desc\",\"category\":\"HOME\",\"price_cents\":1200,\"stock_qty\":1,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "403" ]
grep -F 'Seller account must be approved before listing products' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# No public delete endpoint is visible in the provided call graph.

echo 'CODEVALID_TEST_ASSERTION_OK:pending_seller_cannot_list_products'
