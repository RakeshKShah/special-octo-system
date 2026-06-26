#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_books_user_${CASE_SUFFIX}"
SELLER_ID="cv_seller_003_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('$SELLER_USER_ID', 'books-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Book Store', 'All about books');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO products (id, seller_id, title, description, category, price_cents, stock_qty, photos, status, visible) VALUES ('cv_book_1_${CASE_SUFFIX}', '$SELLER_ID', 'Book 1', 'Desc', 'books', 1000, 10, '[]', 'ACTIVE', true), ('cv_book_2_${CASE_SUFFIX}', '$SELLER_ID', 'Book 2', 'Desc', 'books', 1100, 9, '[]', 'ACTIVE', true), ('cv_book_3_${CASE_SUFFIX}', '$SELLER_ID', 'Book 3', 'Desc', 'books', 1200, 8, '[]', 'ACTIVE', true), ('cv_book_4_${CASE_SUFFIX}', '$SELLER_ID', 'Book 4', 'Desc', 'books', 1300, 7, '[]', 'ACTIVE', true), ('cv_book_5_${CASE_SUFFIX}', '$SELLER_ID', 'Book 5', 'Desc', 'books', 1400, 6, '[]', 'ACTIVE', true);"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
ACTUAL_COUNT=$(jq -r --arg id "$SELLER_ID" '.[] | select(.id == $id) | .product_count' "$RESPONSE_FILE")
[ "$ACTUAL_COUNT" = "5" ]
jq -e --arg id "$SELLER_ID" '.[] | select(.id == $id and .store_name == "Book Store")' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects via trap

echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_product_count_accuracy'
