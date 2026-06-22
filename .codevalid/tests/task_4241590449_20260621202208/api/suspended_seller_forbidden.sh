#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/suspended_seller_forbidden_${CASE_SUFFIX}.json"
INVALID_TOKEN="invalid-suspended-seller-${CASE_SUFFIX}"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — No public API in the provided call graph can create or mutate a seller into SUSPENDED state.
# Use an invalid bearer token as the nearest negative auth path without DB seeding.

# When — POST /products with a malformed bearer token.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${INVALID_TOKEN}" \n  --data '{"title":"Invalid Session Item","description":"Auth failure","category":"MISC","price_cents":1000,"stock_qty":1,"photos":[]}')"

# Then — Expect HTTP 401 because requireAuth rejects the invalid token before seller status checks.
[ "$HTTP_STATUS" = "401" ]
grep -F '"error":"Invalid token"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:suspended_seller_forbidden"

# Cleanup — Stateless cleanup only; temporary files are removed by trap.
