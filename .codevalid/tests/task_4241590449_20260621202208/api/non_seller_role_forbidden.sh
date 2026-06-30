#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="buyer-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!Aa"
RESPONSE_FILE="$(mktemp)"
REGISTER_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"Buyer Product ${CASE_SUFFIX}\",\"description\":\"desc\",\"category\":\"HOME\",\"price_cents\":1200,\"stock_qty\":1,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "403" ]
grep -F 'Seller access required' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# Stateless aside from created buyer account; no public delete endpoint is visible in the provided call graph.

echo 'CODEVALID_TEST_ASSERTION_OK:non_seller_role_forbidden'
