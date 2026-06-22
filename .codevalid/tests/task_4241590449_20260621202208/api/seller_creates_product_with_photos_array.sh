#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_photos_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/seller_creates_product_with_photos_array_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_creates_product_with_photos_array_${CASE_SUFFIX}.json"
PHOTO_ONE="https://cdn.example.com/p1.jpg"
PHOTO_TWO="https://cdn.example.com/p2.jpg"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"Photo Store ${CASE_SUFFIX}","bio":"Photo inventory"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products including multiple photos.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"Photo Product ${CASE_SUFFIX}","description":"Multi photo product","category":"HOME_GOODS","price_cents":3300,"stock_qty":7,"photos":["${PHOTO_ONE}","${PHOTO_TWO}"]}")"

# Then — Expect HTTP 201 and both photos echoed in the response JSON.
[ "$HTTP_STATUS" = "201" ]
grep -F "${PHOTO_ONE}" "$RESPONSE_FILE" >/dev/null
grep -F "${PHOTO_TWO}" "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"Photo Product ' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_creates_product_with_photos_array"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
