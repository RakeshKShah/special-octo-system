#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_invalid_values_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/seller_invalid_price_and_stock_returns_400_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_invalid_price_and_stock_returns_400_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"Invalid Values Store ${CASE_SUFFIX}","bio":"Validation case"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products with invalid negative price and stock quantity.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data '{"title":"Invalid Item","description":"Invalid price/qty","category":"MISC","price_cents":-100,"stock_qty":-5,"photos":[]}')"

# Then — Expect HTTP 400 with a validation error payload.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_invalid_price_and_stock_returns_400"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
