#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="seller_dashboard_products_ordering_$(date +%s)_$$"
SELLER_EMAIL="${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Passw0rd!123"
STORE_NAME="Ordering Shop ${CASE_SUFFIX}"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
REG_FILE="/tmp/${CASE_SUFFIX}_register.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null 2>&1 || true
DELETE FROM "Product" WHERE id IN ('prod-old-${CASE_SUFFIX}','prod-mid-${CASE_SUFFIX}','prod-new-${CASE_SUFFIX}');
DELETE FROM "SellerProfile" WHERE "storeName" = '${STORE_NAME}';
DELETE FROM "User" WHERE email = '${SELLER_EMAIL}';
SQL
  rm -f "$RESP_FILE" "$REG_FILE"
}
trap cleanup EXIT

# Given — create active seller and three products with fixed creation dates.
register_status="$(curl -sS -o "$REG_FILE" -w '%{http_code}' -X POST "$BASE_URL/register" -H 'Content-Type: application/json' --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"${SELLER_PASSWORD}\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"Ordering test\"}")"
[ "$register_status" = "201" ]
TOKEN="$(jq -r '.token' "$REG_FILE")"
SELLER_USER_ID="$(jq -r '.user.id' "$REG_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$REG_FILE")"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 <<SQL >/dev/null
UPDATE "User" SET status = 'ACTIVE' WHERE id = '${SELLER_USER_ID}';
INSERT INTO "Product" (id, "sellerId", title, description, category, "priceCents", "stockQty", photos, status, visible, "createdAt", "updatedAt") VALUES
('prod-old-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Old Product', 'Old desc', 'HOME', 1000, 1, '["https://example.test/old.jpg"]', 'ACTIVE', true, TIMESTAMP '2024-01-01 00:00:00', TIMESTAMP '2024-01-01 00:00:00'),
('prod-mid-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'Mid Product', 'Mid desc', 'HOME', 1000, 1, '["https://example.test/mid.jpg"]', 'ACTIVE', true, TIMESTAMP '2024-03-10 00:00:00', TIMESTAMP '2024-03-10 00:00:00'),
('prod-new-${CASE_SUFFIX}', '${SELLER_PROFILE_ID}', 'New Product', 'New desc', 'HOME', 1000, 1, '["https://example.test/new.jpg"]', 'ACTIVE', true, TIMESTAMP '2024-06-15 00:00:00', TIMESTAMP '2024-06-15 00:00:00');
SQL

# When — fetch seller dashboard.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard" -H "Authorization: Bearer ${TOKEN}")"

# Then — products are returned newest-first.
[ "$status" = "200" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq '.products | length' "$RESP_FILE")" = "3" ]
  [ "$(jq -r '.products[0].title' "$RESP_FILE")" = "New Product" ]
  [ "$(jq -r '.products[1].title' "$RESP_FILE")" = "Mid Product" ]
  [ "$(jq -r '.products[2].title' "$RESP_FILE")" = "Old Product" ]
else
  grep -F 'New Product' "$RESP_FILE" >/dev/null
  grep -F 'Mid Product' "$RESP_FILE" >/dev/null
  grep -F 'Old Product' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_products_ordering"

# Cleanup — remove seeded DB rows.
