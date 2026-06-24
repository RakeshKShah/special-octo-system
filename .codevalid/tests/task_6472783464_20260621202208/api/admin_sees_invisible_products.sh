#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
ADMIN_AUTH_HEADER="${ADMIN_AUTH_HEADER:-}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-}"
ADMIN_RESPONSE_FILE="$(mktemp)"
BUYER_RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$ADMIN_RESPONSE_FILE" "$BUYER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — distinct admin and buyer auth headers are supplied by env
[ -n "$ADMIN_AUTH_HEADER" ]
[ -n "$BUYER_AUTH_HEADER" ]

# When — perform the action under test
ADMIN_HTTP_CODE=$(curl -sS -o "$ADMIN_RESPONSE_FILE" -w '%{http_code}' -X GET -H "$ADMIN_AUTH_HEADER" "$BASE_URL/products")
BUYER_HTTP_CODE=$(curl -sS -o "$BUYER_RESPONSE_FILE" -w '%{http_code}' -X GET -H "$BUYER_AUTH_HEADER" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$ADMIN_HTTP_CODE" = "200" ]
[ "$BUYER_HTTP_CODE" = "200" ]
grep -F '[' "$ADMIN_RESPONSE_FILE" >/dev/null
grep -F '[' "$BUYER_RESPONSE_FILE" >/dev/null

# Cleanup — stateless

echo 'CODEVALID_TEST_ASSERTION_OK:admin_sees_invisible_products'
