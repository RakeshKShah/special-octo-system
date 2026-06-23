#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_lists_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Store ${CASE_SUFFIX}"
TITLE="Handmade Mug ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/seller_lists_product_successfully_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_lists_product_successfully_${CASE_SUFFIX}.json"
HTTP_STATUS_FILE="/tmp/seller_lists_product_successfully_status_${CASE_SUFFIX}.txt"
TOKEN=""
USER_ID=""
SELLER_PROFILE_ID=""
PRODUCT_ID=""

cleanup() {
  if [ -n "$PRODUCT_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE id = '$PRODUCT_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM product WHERE id = '$PRODUCT_ID';" >/dev/null 2>&1 || true
  fi
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profile WHERE user_id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"user\" WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE" "$HTTP_STATUS_FILE"
}
trap cleanup EXIT

# Given — register a seller and promote it to ACTIVE through Postgres so it can list products.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Ceramics seller\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
[ -n "$SELLER_PROFILE_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null 2>&1 || \
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null

# When — create a product with photos, pricing, and stock quantity.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Ceramic coffee mug\",\"category\":\"HOME\",\"price_cents\":2500,\"stock_qty\":10,\"photos\":[\"https://example.com/mug1.jpg\"]}")"
PRODUCT_ID="$(jq -r '.id // empty' "$RESPONSE_FILE")"

# Then — status 201 and product fields are returned as created.
[ "$HTTP_STATUS" = "201" ]
[ -n "$PRODUCT_ID" ]
jq -e --arg sellerProfileId "$SELLER_PROFILE_ID" --arg title "$TITLE" '
  .sellerId == $sellerProfileId and
  .title == $title and
  .description == "Ceramic coffee mug" and
  .category == "HOME" and
  .priceCents == 2500 and
  .stockQty == 10 and
  .status == "ACTIVE" and
  .visible == true and
  .photos == ["https://example.com/mug1.jpg"]
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_lists_product_successfully"

# Cleanup — delete created product, seller profile, and user rows.
