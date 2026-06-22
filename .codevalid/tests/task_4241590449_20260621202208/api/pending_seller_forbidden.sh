#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_pending_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/pending_seller_forbidden_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/pending_seller_forbidden_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a seller account; the register route sets seller status to PENDING.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"Pending Store ${CASE_SUFFIX}","bio":"Pending approval"}")"
[ "$REGISTER_STATUS" = "201" ]
grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]

# When — POST /products with a PENDING seller token.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"Pending Seller Product ${CASE_SUFFIX}","description":"Blocked until approval","category":"HOME_GOODS","price_cents":2200,"stock_qty":4,"photos":[]}")"

# Then — Expect HTTP 403 with pending seller approval error.
[ "$HTTP_STATUS" = "403" ]
grep -F '"error":"Seller account must be approved before listing products"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:pending_seller_forbidden"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
