#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Camera Shop ${CASE_SUFFIX}"
STORE_BIO="Vintage gear ${CASE_SUFFIX}"
TITLE="Vintage Camera ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/seller_creates_product_successfully_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/seller_creates_product_successfully_${CASE_SUFFIX}.json"
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

# Given — register a unique seller and approve the seller account for listing.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${STORE_BIO}\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When — create a product with valid title, description, category, price, stock, and photos.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Classic film camera\",\"category\":\"Electronics\",\"price_cents\":15999,\"stock_qty\":5,\"photos\":[\"photo1.jpg\",\"photo2.jpg\"]}")"

# Then — response is 201 and the returned product includes ACTIVE status and visible=true.
[ "$HTTP_STATUS" = "201" ]
grep -F "\"title\":\"${TITLE}\"" "$RESPONSE_FILE" >/dev/null
grep -F '"description":"Classic film camera"' "$RESPONSE_FILE" >/dev/null
grep -F '"category":"Electronics"' "$RESPONSE_FILE" >/dev/null
grep -F '"priceCents":15999' "$RESPONSE_FILE" >/dev/null
grep -F '"stockQty":5' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"ACTIVE"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null
grep -F '"photos":["photo1.jpg","photo2.jpg"]' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_creates_product_successfully"

# Cleanup — remove the created seller user; related profile/products should cascade or be detached by the app schema.
