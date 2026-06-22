#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_no_profile_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
STORE_NAME="No Profile Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"
USER_ID=""

cleanup() {
  if [ -n "${USER_ID}" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "SellerProfile" WHERE "userId" = '${USER_ID}';
DELETE FROM "User" WHERE id = '${USER_ID}';
SQL
  fi
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create seller, activate seller, then delete seller profile.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Missing profile\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
USER_ID="$(jq -r '.user.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${USER_ID}';
DELETE FROM "SellerProfile" WHERE "userId" = '${USER_ID}';
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — endpoint returns seller profile not found.
[ "$status" = "404" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.error' "$RESP_FILE")" = "Seller profile not found" ]
else
  grep -F 'Seller profile not found' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_no_profile"

# Cleanup — remove seeded DB rows.
