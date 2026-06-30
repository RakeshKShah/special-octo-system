#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="photos-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Photo Shop ${CASE_SUFFIX}"
TITLE="Antique Watch ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/product_created_with_photos_array_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/product_created_with_photos_array_${CASE_SUFFIX}.json"
USER_ID=""
TOKEN=""

cleanup() {
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
  else
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register and activate a unique seller.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",store_name:\"${STORE_NAME}\",\"bio\":\"photos\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When — create a product that includes multiple photos.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Gold pocket watch from 1920s\",\"category\":\"Jewelry\",\"price_cents\":45000,\"stock_qty\":1,\"photos\":[\"img1.jpg\",\"img2.jpg\",\"img3.jpg\"]}")"

# Then — response is 201 and the photos array is preserved in the product body.
[ "$HTTP_STATUS" = "201" ]
grep -F "\"title\":\"${TITLE}\"" "$RESPONSE_FILE" >/dev/null
grep -F '"photos":["img1.jpg","img2.jpg","img3.jpg"]' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_created_with_photos_array"

# Cleanup — remove the created seller account.
