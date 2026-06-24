#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
SELLER_USER_ID="cv_user_new_${CASE_SUFFIX}"
SELLER_ID="cv_seller_new_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE \"sellerId\" = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE id = '$SELLER_ID';" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$SELLER_USER_ID';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, \"passwordHash\", role, status, \"createdAt\") VALUES ('$SELLER_USER_ID', 'fresh-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW());"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"SellerProfile\" (id, \"userId\", \"storeName\", bio) VALUES ('$SELLER_ID', '$SELLER_USER_ID', 'Fresh Start', 'Starting out');"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/sellers")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
ACTUAL_COUNT=$(jq -r --arg id "$SELLER_ID" '.[] | select(.id == $id) | .product_count' "$RESPONSE_FILE")
[ "$ACTUAL_COUNT" = "0" ]
jq -e --arg id "$SELLER_ID" '.[] | select(.id == $id and .store_name == "Fresh Start")' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects via trap

echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_zero_product_count'
