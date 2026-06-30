#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="soldout-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="Sold Out Shop ${CASE_SUFFIX}"
TITLE="Out of Stock Item ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/zero_stock_sets_sold_out_status_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/zero_stock_sets_sold_out_status_${CASE_SUFFIX}.json"
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
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",store_name:\"${STORE_NAME}\",\"bio\":\"sold out\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null

# When — create a product with stock_qty set to 0.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Currently unavailable\",\"category\":\"Misc\",\"price_cents\":999,\"stock_qty\":0,\"photos\":[]}")"

# Then — response is 201 and product status is SOLD_OUT with visible=true.
[ "$HTTP_STATUS" = "201" ]
grep -F "\"title\":\"${TITLE}\"" "$RESPONSE_FILE" >/dev/null
grep -F 'stock_qty:0' "$RESPONSE_FILE" >/dev/null
grep -F '"status":"SOLD_OUT"' "$RESPONSE_FILE" >/dev/null
grep -F '"visible":true' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:zero_stock_sets_sold_out_status"

# Cleanup — remove the created seller account.
