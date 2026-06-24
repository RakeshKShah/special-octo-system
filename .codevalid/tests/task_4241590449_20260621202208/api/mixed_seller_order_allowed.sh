#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
REGISTER_RESPONSE_FILE="$(mktemp)"
ORDER_ID="order-mixed-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-mixed-${CASE_SUFFIX}@example.com"
SELLER1_EMAIL="seller-mixed-one-${CASE_SUFFIX}@example.com"
SELLER2_EMAIL="seller-mixed-two-${CASE_SUFFIX}@example.com"
PRODUCT1_ID="prod-mixed-one-${CASE_SUFFIX}"
PRODUCT2_ID="prod-mixed-two-${CASE_SUFFIX}"
ORDER_ITEM1_ID="order-item-mixed-one-${CASE_SUFFIX}"
ORDER_ITEM2_ID="order-item-mixed-two-${CASE_SUFFIX}"
SELLER1_TOKEN=""
SELLER1_USER_ID=""
SELLER1_PROFILE_ID=""
SELLER2_USER_ID=""
SELLER2_PROFILE_ID=""
BUYER_USER_ID=""
cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"OrderItem\" WHERE id IN ('$ORDER_ITEM1_ID', '$ORDER_ITEM2_ID')" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Order\" WHERE id = '$ORDER_ID'" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$PRODUCT1_ID', '$PRODUCT2_ID')" >/dev/null 2>&1 || true
  [ -n "$SELLER1_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER1_USER_ID'" >/dev/null 2>&1 || true
  [ -n "$SELLER2_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER2_USER_ID'" >/dev/null 2>&1 || true
  [ -n "$BUYER_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$BUYER_USER_ID'" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$REGISTER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER1_EMAIL\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"Store 1 $CASE_SUFFIX\",\"bio\":\"Bio\"}" "$BASE_URL/register")
[ "$HTTP_CODE" = "201" ]
SELLER1_TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
SELLER1_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
SELLER1_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '$SELLER1_USER_ID'" >/dev/null
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER2_EMAIL\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"Store 2 $CASE_SUFFIX\",\"bio\":\"Bio\"}" "$BASE_URL/register")
[ "$HTTP_CODE" = "201" ]
SELLER2_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
SELLER2_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '$SELLER2_USER_ID'" >/dev/null
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$BUYER_EMAIL\",\"password\":\"Password123!\",\"role\":\"BUYER\"}" "$BASE_URL/register")
[ "$HTTP_CODE" = "201" ]
BUYER_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", photos, status, visible, \"createdAt\", \"updatedAt\") VALUES ('$PRODUCT1_ID', '$SELLER1_PROFILE_ID', 'Product 1 $CASE_SUFFIX', 'Seeded product', 'GENERAL', 2500, 5, '[]', 'ACTIVE', true, NOW(), NOW())" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", photos, status, visible, \"createdAt\", \"updatedAt\") VALUES ('$PRODUCT2_ID', '$SELLER2_PROFILE_ID', 'Product 2 $CASE_SUFFIX', 'Seeded product', 'GENERAL', 2600, 5, '[]', 'ACTIVE', true, NOW(), NOW())" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Order\" (id, \"buyerId\", status, \"createdAt\", \"updatedAt\") VALUES ('$ORDER_ID', '$BUYER_USER_ID', 'PAID', NOW(), NOW())" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"OrderItem\" (id, \"orderId\", \"productId\", qty, \"sellerPayoutCents\") VALUES ('$ORDER_ITEM1_ID', '$ORDER_ID', '$PRODUCT1_ID', 1, 2000)" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"OrderItem\" (id, \"orderId\", \"productId\", qty, \"sellerPayoutCents\") VALUES ('$ORDER_ITEM2_ID', '$ORDER_ID', '$PRODUCT2_ID', 1, 2100)" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $SELLER1_TOKEN" "$BASE_URL/orders/$ORDER_ID/ship")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
grep -F '"success":true' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SHIPPED"' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "SELECT status FROM \"Order\" WHERE id = '$ORDER_ID'")"
[ "$DB_STATUS" = "SHIPPED" ]

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:mixed_seller_order_allowed'
