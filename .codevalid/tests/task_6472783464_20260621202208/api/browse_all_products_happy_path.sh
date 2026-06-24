#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — endpoint is public/optionalAuth; authenticated buyer header may be provided by env

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

echo 'CODEVALID_TEST_ASSERTION_OK:browse_all_products_happy_path'
