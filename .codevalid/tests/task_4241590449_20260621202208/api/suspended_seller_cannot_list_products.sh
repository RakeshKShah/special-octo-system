#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
TOKEN="${SUSPENDED_SELLER_TOKEN:-}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
[ -n "$TOKEN" ] || { echo 'SUSPENDED_SELLER_TOKEN must be provided for a suspended seller because no public API to suspend a seller is visible in the call graph' >&2; exit 1; }

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"Suspended Product ${CASE_SUFFIX}\",\"description\":\"desc\",\"category\":\"HOME\",\"price_cents\":1200,\"stock_qty\":1,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "403" ]
grep -F 'Suspended sellers cannot create products' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# Stateless.

echo 'CODEVALID_TEST_ASSERTION_OK:suspended_seller_cannot_list_products'
