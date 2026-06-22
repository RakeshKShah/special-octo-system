#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_missing_title_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/seller_missing_required_fields_returns_400_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_missing_required_fields_returns_400_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique seller account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"Missing Title Store ${CASE_SUFFIX}","bio":"Validation case"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products missing the required title field.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data '{"description":"No title","category":"HOME_GOODS","price_cents":1000,"stock_qty":5,"photos":[]}')"

# Then — Expect HTTP 400 with an error payload.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_missing_required_fields_returns_400"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
