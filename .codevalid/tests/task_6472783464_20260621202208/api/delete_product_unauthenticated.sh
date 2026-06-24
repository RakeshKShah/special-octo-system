#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
PRODUCT_ID="${PRODUCT_ID:-prod-102}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no authentication header is provided

# When — unauthenticated caller attempts product deletion
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE "$BASE_URL/products/$PRODUCT_ID")

# Then — auth middleware rejects the request
case "$HTTP_CODE" in
  401|403) ;;
  *) echo "Expected 401 or 403 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1 ;;
esac
grep -E 'error|auth|token|forbidden|unauthorized' "$RESPONSE_FILE" >/dev/null || { echo "Expected auth-related error payload"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:delete_product_unauthenticated'
