#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="zero-stock-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!Aa"
STORE_NAME="Store-${CASE_SUFFIX}"
BIO="Bio-${CASE_SUFFIX}"
PRODUCT_TITLE="Limited Edition Print ${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"
REGISTER_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"SELLER\",\"storeName\":\"$STORE_NAME\",\"bio\":\"$BIO\"}" "$BASE_URL/register")
[ "$HTTP_CODE" = "201" ]
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
if grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null 2>&1; then
  echo 'seller registered as PENDING; zero-stock creation case requires an active seller token in this environment' >&2
  cat "$REGISTER_FILE" >&2
  exit 1
fi

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"$PRODUCT_TITLE\",\"description\":\"Art print\",\"category\":\"ART\",\"price_cents\":10000,\"stock_qty\":0,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "201" ]
grep -F "$PRODUCT_TITLE" "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":0' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SOLD_OUT"' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# No supported public delete endpoint is visible in the provided call graph.

echo 'CODEVALID_TEST_ASSERTION_OK:product_is_sold_out_when_zero_stock'
