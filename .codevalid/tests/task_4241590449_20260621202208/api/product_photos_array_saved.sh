#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="photos_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!${CASE_SUFFIX}"
TITLE="Stool ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/product_photos_array_saved_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/product_photos_array_saved_${CASE_SUFFIX}.json"
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
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '$USER_ID';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register a seller and promote it to ACTIVE.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"Photo Store ${CASE_SUFFIX}\",\"bio\":\"Temp\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$REGISTER_FILE")"
USER_ID="$(jq -r '.user.id' "$REGISTER_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REGISTER_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null 2>&1 || \
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '$USER_ID';" >/dev/null

# When — create a product with multiple photos.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Wooden stool\",\"category\":\"FURNITURE\",\"price_cents\":8000,\"stock_qty\":3,\"photos\":[\"https://example.com/stool1.jpg\",\"https://example.com/stool2.jpg\"]}")"
PRODUCT_ID="$(jq -r '.id // empty' "$RESPONSE_FILE")"

# Then — status 201 and the exact photos array is echoed back.
[ "$HTTP_STATUS" = "201" ]
[ -n "$PRODUCT_ID" ]
jq -e --arg sellerProfileId "$SELLER_PROFILE_ID" --arg title "$TITLE" '
  .sellerId == $sellerProfileId and
  .title == $title and
  .photos == ["https://example.com/stool1.jpg", "https://example.com/stool2.jpg"]
' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_photos_array_saved"

# Cleanup — delete created product, seller profile, and user rows.
