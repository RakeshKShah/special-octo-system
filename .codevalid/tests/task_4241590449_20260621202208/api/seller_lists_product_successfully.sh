#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-success-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!Aa"
STORE_NAME="Store-${CASE_SUFFIX}"
BIO="Bio-${CASE_SUFFIX}"
PRODUCT_TITLE="Handmade Mug ${CASE_SUFFIX}"
PRODUCT_DESCRIPTION="Ceramic coffee mug"
RESPONSE_FILE="$(mktemp)"
REGISTER_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"SELLER\",store_name:\"$STORE_NAME\",\"bio\":\"$BIO\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
if grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null 2>&1; then
  echo 'seller registered as PENDING; product creation cannot succeed without prior approval' >&2
  cat "$REGISTER_FILE" >&2
  exit 1
fi

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"$PRODUCT_TITLE\",\"description\":\"$PRODUCT_DESCRIPTION\",\"category\":\"HOME\",\"price_cents\":2500,\"stock_qty\":10,\"photos\":[\"https://example.com/mug1.jpg\"]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "201" ]
grep -F '"title":"' "$RESPONSE_FILE" >/dev/null
grep -F "$PRODUCT_TITLE" "$RESPONSE_FILE" >/dev/null
grep -F '"description":"Ceramic coffee mug"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"HOME"' "$RESPONSE_FILE" >/dev/null
grep -F 'price_cents:2500' "$RESPONSE_FILE" >/dev/null
grep -F 'stock_qty:10' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
grep -F 'https://example.com/mug1.jpg' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# No supported public delete endpoint is visible in the provided call graph.

echo 'CODEVALID_TEST_ASSERTION_OK:seller_lists_product_successfully'
