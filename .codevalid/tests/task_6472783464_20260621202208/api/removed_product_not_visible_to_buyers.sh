#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-106}"
BEFORE_FILE="$(mktemp)"
DELETE_FILE="$(mktemp)"
AFTER_FILE="$(mktemp)"

cleanup() {
  rm -f "$BEFORE_FILE" "$DELETE_FILE" "$AFTER_FILE"
}
trap cleanup EXIT

# Given — product is visible to buyers before deletion
BEFORE_CODE=$(curl -sS -o "$BEFORE_FILE" -w '%{http_code}' "$BASE_URL/products")
[ "$BEFORE_CODE" = "200" ] || { echo "Expected 200 from initial browse got $BEFORE_CODE"; cat "$BEFORE_FILE"; exit 1; }
grep -F "$PRODUCT_ID" "$BEFORE_FILE" >/dev/null || { echo "Expected product to appear before deletion"; cat "$BEFORE_FILE"; exit 1; }
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller removes the product and buyer browses again
DELETE_CODE=$(curl -sS -o "$DELETE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")
[ "$DELETE_CODE" = "200" ] || { echo "Expected 200 from delete got $DELETE_CODE"; cat "$DELETE_FILE"; exit 1; }
AFTER_CODE=$(curl -sS -o "$AFTER_FILE" -w '%{http_code}' "$BASE_URL/products")

# Then — removed product is no longer listed to buyers
[ "$AFTER_CODE" = "200" ] || { echo "Expected 200 from follow-up browse got $AFTER_CODE"; cat "$AFTER_FILE"; exit 1; }
if grep -F "$PRODUCT_ID" "$AFTER_FILE" >/dev/null; then
  echo "Expected removed product to be absent from buyer listing"
  cat "$AFTER_FILE"
  exit 1
fi

# Cleanup — none

echo 'CODEVALID_TEST_ASSERTION_OK:removed_product_not_visible_to_buyers'
