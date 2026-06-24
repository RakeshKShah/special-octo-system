#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
BUYER_ID="buyer-${CASE_SUFFIX}"
OTHER_BUYER_ID="other-buyer-${CASE_SUFFIX}"
SELLER_USER_ID="seller-user-${CASE_SUFFIX}"
SELLER_PROFILE_ID="seller-profile-${CASE_SUFFIX}"
PRODUCT_ID="prod-${CASE_SUFFIX}"
ORDER_ID="order-${CASE_SUFFIX}"
ORDER_ITEM_ID="orderitem-${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"
LOGIN_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$RESPONSE_FILE" "$LOGIN_FILE"
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Review\" WHERE \"orderItemId\" = '$ORDER_ITEM_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"OrderItem\" WHERE id = '$ORDER_ITEM_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Order\" WHERE id = '$ORDER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id = '$PRODUCT_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE id = '$SELLER_PROFILE_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id IN ('$BUYER_ID', '$OTHER_BUYER_ID', '$SELLER_USER_ID');" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, password, role) VALUES ('$BUYER_ID', 'buyer-$CASE_SUFFIX@example.com', 'password123', 'BUYER'), ('$OTHER_BUYER_ID', 'other-buyer-$CASE_SUFFIX@example.com', 'password123', 'BUYER'), ('$SELLER_USER_ID', 'seller-$CASE_SUFFIX@example.com', 'password123', 'SELLER');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"SellerProfile\" (id, \"userId\", \"storeName\") VALUES ('$SELLER_PROFILE_ID', '$SELLER_USER_ID', 'Store $CASE_SUFFIX');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible) VALUES ('$PRODUCT_ID', '$SELLER_PROFILE_ID', 'Product $CASE_SUFFIX', 'Review product', 'craft', 1200, 5, 'ACTIVE', true);" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Order\" (id, \"buyerId\", \"totalCents\", \"platformFeeCents\", status) VALUES ('$ORDER_ID', '$OTHER_BUYER_ID', 1200, 120, 'DELIVERED');" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"OrderItem\" (id, \"orderId\", \"productId\", \"sellerId\", qty, \"priceAtPurchase\", \"sellerPayoutCents\") VALUES ('$ORDER_ITEM_ID', '$ORDER_ID', '$PRODUCT_ID', '$SELLER_PROFILE_ID', 1, 1200, 1080);" >/dev/null
HTTP_CODE=$(curl -sS -o "$LOGIN_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"buyer-$CASE_SUFFIX@example.com\",\"password\":\"password123\"}" "$BASE_URL/auth/login")
[ "$HTTP_CODE" = "200" ]
TOKEN=$(jq -r '.token // .accessToken // .jwt // empty' "$LOGIN_FILE")
[ -n "$TOKEN" ]

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"order_item_id\":\"$ORDER_ITEM_ID\",\"rating\":2,\"body\":\"Not my order\"}" "$BASE_URL/reviews")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "404" ]
grep -F 'Order item not found' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# handled by trap

echo 'CODEVALID_TEST_ASSERTION_OK:review_rejected_wrong_buyer_ownership'
