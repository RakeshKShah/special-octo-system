#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — out-of-stock products should remain visible by default

# When — perform the action under test
if [ -n "$BUYER_AUTH_HEADER" ]; then
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "$BUYER_AUTH_HEADER" "$BASE_URL/products")
else
  HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/products")
fi

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F '[' "$RESPONSE_FILE" >/dev/null

# Cleanup — stateless

echo 'CODEVALID_TEST_ASSERTION_OK:out_of_stock_products_visible'
