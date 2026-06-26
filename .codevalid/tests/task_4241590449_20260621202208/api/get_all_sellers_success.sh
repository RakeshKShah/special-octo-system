#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER1_USER_ID="cv_user_101_${CASE_SUFFIX}"
SELLER1_ID="cv_seller_001_${CASE_SUFFIX}"
SELLER2_USER_ID="cv_user_102_${CASE_SUFFIX}"
SELLER2_ID="cv_seller_002_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id IN ('$SELLER1_ID', '$SELLER2_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id IN ('$SELLER1_ID', '$SELLER2_ID');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id IN ('$SELLER1_USER_ID', '$SELLER2_USER_ID');" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('$SELLER1_USER_ID', 'artisan-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', TIMESTAMP WITH TIME ZONE '2024-01-15T10:00:00Z'), ('$SELLER2_USER_ID', 'tech-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', TIMESTAMP WITH TIME ZONE '2024-01-10T08:00:00Z');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('$SELLER1_ID', '$SELLER1_USER_ID', 'Artisan Crafts', 'Handmade goods'), ('$SELLER2_ID', '$SELLER2_USER_ID', 'Tech Gadgets', 'Latest tech');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('cv_prod_a1_${CASE_SUFFIX}', '$SELLER1_ID', 'Craft Item 1', 'Desc', 'crafts', 1200, 5, '[]', 'ACTIVE', true), ('cv_prod_a2_${CASE_SUFFIX}', '$SELLER1_ID', 'Craft Item 2', 'Desc', 'crafts', 1300, 4, '[]', 'ACTIVE', true), ('cv_prod_a3_${CASE_SUFFIX}', '$SELLER1_ID', 'Craft Item 3', 'Desc', 'crafts', 1400, 3, '[]', 'ACTIVE', true), ('cv_prod_b1_${CASE_SUFFIX}', '$SELLER2_ID', 'Gadget 1', 'Desc', 'tech', 2500, 6, '[]', 'ACTIVE', true);"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
FIRST_ID=$(jq -r '.[0].id' "$RESPONSE_FILE")
SECOND_COUNT=$(jq -r '.[1].product_count' "$RESPONSE_FILE")
[ "$FIRST_ID" = "$SELLER1_ID" ]
[ "$SECOND_COUNT" = "1" ]
jq -e --arg id "$SELLER1_ID" --arg user_id "$SELLER1_USER_ID" '.[] | select(.id == $id and .user_id == $user_id and .store_name == "Artisan Crafts" and .bio == "Handmade goods" and .status == "ACTIVE" and .product_count == 3)' "$RESPONSE_FILE" >/dev/null
jq -e --arg id "$SELLER2_ID" '.[] | select(.id == $id and .store_name == "Tech Gadgets" and .bio == "Latest tech" and .product_count == 1)' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects via trap

echo 'CODEVALID_TEST_ASSERTION_OK:get_all_sellers_success'
