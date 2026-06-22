#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_EMAIL="buyer_forbidden_${CASE_SUFFIX}@example.com"
BUYER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/non_seller_role_forbidden_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/non_seller_role_forbidden_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a unique BUYER account and capture its bearer token.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${BUYER_EMAIL}","password":"${BUYER_PASSWORD}","role":"BUYER"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products using a non-seller authenticated user.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"Buyer Cannot Create ${CASE_SUFFIX}","description":"Forbidden","category":"HOME_GOODS","price_cents":1500,"stock_qty":3,"photos":[]}")"

# Then — Expect HTTP 403 with seller access required error.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Seller access required"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:non_seller_role_forbidden"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
