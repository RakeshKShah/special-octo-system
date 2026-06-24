#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TOKEN="${SELLER_WITHOUT_PROFILE_TOKEN:-}"
RESPONSE_FILE="$(mktemp)"
CASE_SUFFIX="$(date +%s)-$$"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
[ -n "$TOKEN" ] || { echo 'SELLER_WITHOUT_PROFILE_TOKEN must be provided for an active seller without a seller profile because registration auto-creates sellerProfile and no public API to remove it is visible in the call graph' >&2; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"No Profile Product ${CASE_SUFFIX}\",\"description\":\"desc\",\"category\":\"HOME\",\"price_cents\":1200,\"stock_qty\":1,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ]
grep -F 'Seller profile not found' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# Stateless.

echo 'CODEVALID_TEST_ASSERTION_OK:seller_profile_not_found'
