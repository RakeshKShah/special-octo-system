#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_active_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
STORE_NAME="Active Store ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/seller_creates_active_product_success_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_creates_active_product_success_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"${STORE_NAME}","bio":"Ceramic goods"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products with valid product data and positive stock quantity.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"Handcrafted Mug ${CASE_SUFFIX}","description":"Ceramic mug","category":"HOME_GOODS","price_cents":2500,"stock_qty":10,"photos":["https://cdn.example.com/mug1.jpg"]}")"

# Then — Expect HTTP 201 and product JSON containing ACTIVE status and visible true.
[ "$HTTP_STATUS" = "201" ]
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":10' "$RESPONSE_FILE" >/dev/null
grep -F '"title":"Handcrafted Mug '
