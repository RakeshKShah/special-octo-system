#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_soldout_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/seller_creates_sold_out_product_zero_stock_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_creates_sold_out_product_zero_stock_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"Sold Out Store ${CASE_SUFFIX}","bio":"Art seller"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products with stock_qty 0.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"Vintage Poster ${CASE_SUFFIX}","description":"Limited edition","category":"ART","price_cents":8000,"stock_qty":0,"photos":["https://cdn.example.com/poster1.jpg"]}")"

# Then — Expect HTTP 201 with SOLD_OUT status and visible true.
[ "$HTTP_STATUS" = "201" ]
grep -F '"status":"SOLD_OUT"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"Vintage Poster ' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_creates_sold_out_product_zero_stock"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
