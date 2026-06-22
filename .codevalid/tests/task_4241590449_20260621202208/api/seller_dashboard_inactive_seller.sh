#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_inactive_seller_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
STORE_NAME="Inactive Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create seller and set status to SUSPENDED.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Suspended seller\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE \"User\" SET status = 'SUSPENDED' WHERE id = '${SELLER_USER_ID}';" >/dev/null

# When — fetch seller dashboard with suspended seller token.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — request is rejected by requireActiveSeller.
[ "$status" = "403" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.error' "$RESP_FILE")" = "Seller account must be active" ]
else
  grep -F 'Seller account must be active' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_inactive_seller"

# Cleanup — remove seeded DB rows.
