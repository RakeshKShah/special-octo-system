#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
BUYER_AUTH_HEADER="${BUYER_AUTH_HEADER:-${AUTH_HEADER:-Authorization: Bearer buyer-token}}"

CASE_SUFFIX="$(date +%s)-$$"
SELLER_USER_A="seller-user-a-${CASE_SUFFIX}"
SELLER_USER_B="seller-user-b-${CASE_SUFFIX}"
SELLER_ID_A="seller-A-${CASE_SUFFIX}"
SELLER_ID_B="seller-B-${CASE_SUFFIX}"
PRODUCT_ID_A="prod-111-${CASE_SUFFIX}"
PRODUCT_ID_B="prod-222-${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"
ORDER_ID=""

cleanup() {
  if [ -n "$ORDER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"OrderItem\" WHERE \"orderId\" = '$ORDER_ID'; DELETE FROM \"Order\" WHERE id = '$ORDER_ID';" >/dev/null 2>&1 || true
  fi
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id IN ('$PRODUCT_ID_A', '$PRODUCT_ID_B'); DELETE FROM \"SellerProfile\" WHERE id IN ('$SELLER_ID_A', '$SELLER_ID_B'); DELETE FROM \"User\" WHERE id IN ('$SELLER_USER_A', '$SELLER_USER_B');" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, role) VALUES ('$SELLER_USER_A', 'seller-a-${CASE_SUFFIX}@example.com', 'SELLER'), ('$SELLER_USER_B', 'seller-b-${CASE_SUFFIX}@example.com', 'SELLER') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"SellerProfile\" (id, \"userId\", \"storeName\") VALUES ('$SELLER_ID_A', '$SELLER_USER_A', 'Store A'), ('$SELLER_ID_B', '$SELLER_USER_B', 'Store B') ON CONFLICT (id) DO NOTHING;"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"Product\" (id, \"sellerId\", title, description, category, \"priceCents\", \"stockQty\", status, visible) VALUES ('$PRODUCT_ID_A', '$SELLER_ID_A', 'Item A ${CASE_SUFFIX}', 'First', 'crafts', 1500, 5, 'ACTIVE', true), ('$PRODUCT_ID_B', '$SELLER_ID_B', 'Item B ${CASE_SUFFIX}', 'Second', 'crafts', 3000, 3, 'ACTIVE', true);"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H "$BUYER_AUTH_HEADER" -H 'Content-Type: application/json' -d "{\"items\":[{\"product_id\":\"$PRODUCT_ID_A\",\"qty\":2},{\"product_id\":\"$PRODUCT_ID_B\",\"qty\":1}]}" "$BASE_URL/checkout")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "201" ]
grep -Eq '"totalCents"[[:space:]]*:[[:space:]]*6000' "$RESPONSE_FILE" >/dev/null
grep -Eq '"platformFeeCents"[[:space:]]*:[[:space:]]*[0-9]+' "$RESPONSE_FILE" >/dev/null
QTY_MATCHES="$(grep -o '"qty"[[:space:]]*:[[:space:]]*[0-9]*' "$RESPONSE_FILE" | wc -l | tr -d ' ')"
[ "$QTY_MATCHES" -ge 2 ]
ORDER_ID="$(grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' "$RESPONSE_FILE" | head -1 | cut -d '"' -f4)"
[ -n "$ORDER_ID" ]
STOCK_A="$(psql "$DATABASE_URL" -tAc "SELECT \"stockQty\" FROM \"Product\" WHERE id = '$PRODUCT_ID_A';")"
STOCK_B="$(psql "$DATABASE_URL" -tAc "SELECT \"stockQty\" FROM \"Product\" WHERE id = '$PRODUCT_ID_B';")"
[ "$STOCK_A" = "3" ]
[ "$STOCK_B" = "2" ]

# Cleanup — undo Given side effects

echo 'CODEVALID_TEST_ASSERTION_OK:checkout_happy_path_multiple_items'
