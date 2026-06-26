#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
REGISTER_RESPONSE_FILE="$(mktemp)"
ORDER_ID="order-cancelled-${CASE_SUFFIX}"
BUYER_EMAIL="buyer-cancelled-${CASE_SUFFIX}@example.com"
SELLER_EMAIL="seller-cancelled-${CASE_SUFFIX}@example.com"
PRODUCT_ID="prod-cancelled-${CASE_SUFFIX}"
ORDER_ITEM_ID="order-item-cancelled-${CASE_SUFFIX}"
SELLER_TOKEN=""
SELLER_USER_ID=""
SELLER_PROFILE_ID=""
BUYER_USER_ID=""
cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM order_items WHERE id = '$ORDER_ITEM_ID'" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM orders WHERE id = '$ORDER_ID'" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE id = '$PRODUCT_ID'" >/dev/null 2>&1 || true
  [ -n "$SELLER_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$SELLER_USER_ID'" >/dev/null 2>&1 || true
  [ -n "$BUYER_USER_ID" ] && psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$BUYER_USER_ID'" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$REGISTER_RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$SELLER_EMAIL\",\"password\":\"Password123!\",\"role\":\"SELLER\",\"storeName\":\"Store $CASE_SUFFIX\",\"bio\":\"Bio $CASE_SUFFIX\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
SELLER_TOKEN="$(jq -r '.token' "$REGISTER_RESPONSE_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '$SELLER_USER_ID'" >/dev/null
HTTP_CODE=$(curl -sS -o "$REGISTER_RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$BUYER_EMAIL\",\"password\":\"Password123!\",\"role\":\"BUYER\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
BUYER_USER_ID="$(jq -r '.user.id' "$REGISTER_RESPONSE_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('$PRODUCT_ID', '$SELLER_PROFILE_ID', 'Product $CASE_SUFFIX', 'Seeded product', 'GENERAL', 2500, 5, '[]', 'ACTIVE', true)" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO orders (id, buyer_id, status) VALUES ('$ORDER_ID', '$BUYER_USER_ID', 'CANCELLED')" >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO order_items (id, order_id, product_id, seller_id, qty, price_at_purchase, seller_payout_cents) VALUES ('$ORDER_ITEM_ID', '$ORDER_ID', '$PRODUCT_ID', '$SELLER_PROFILE_ID', 1, 2500, 2000)" >/dev/null

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "Authorization: Bearer $SELLER_TOKEN" "$BASE_URL/orders/$ORDER_ID/ship")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "400" ]
grep -F 'Order not ready to ship' "$RESPONSE_FILE" >/dev/null
DB_STATUS="$(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -tAc "SELECT status FROM orders WHERE id = '$ORDER_ID'")"
[ "$DB_STATUS" = "CANCELLED" ]

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:cancelled_order_rejected'
