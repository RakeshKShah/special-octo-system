#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-${AUTH_HEADER:-Authorization: Bearer buyer-token}}"

CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_ID="seller-${CASE_SUFFIX}"
PRODUCT_ID="prod-soldout-${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id = '$PRODUCT_ID'; DELETE FROM \"SellerProfile\" WHERE id = '$SELLER_ID'; DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, role) VALUES ('$SELLER_USER_ID', 'seller-${CASE_SUFFIX}@example.com', 'SELLER') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"SellerProfile\" (id, \"userId\", \"storeName\") VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Sold Out Store') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible) VALUES ('$PRODUCT_ID', '$SELLER_ID', 'Sold Out ${CASE_SUFFIX}', 'None left', 'crafts', 2500, 0, 'SOLD_OUT', true);"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d "{\"items\":[{\"product_id\":\"$PRODUCT_ID\",\"qty\":1}]}" "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "400" ]
grep -F "Product $PRODUCT_ID unavailable" "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_product_zero_stock'
