#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
USER_ACTIVE="cv_user_active_${CASE_SUFFIX}"
USER_SUSPENDED="cv_user_suspended_${CASE_SUFFIX}"
SELLER_ACTIVE="cv_seller_active_${CASE_SUFFIX}"
SELLER_SUSPENDED="cv_seller_suspended_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"Product\" WHERE \"sellerId\" IN ('$SELLER_ACTIVE', '$SELLER_SUSPENDED');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE id IN ('$SELLER_ACTIVE', '$SELLER_SUSPENDED');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE id IN ('$USER_ACTIVE', '$USER_SUSPENDED');" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, \"passwordHash\", role, status, \"createdAt\") VALUES ('$USER_ACTIVE', 'active-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', NOW()), ('$USER_SUSPENDED', 'suspended-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'SUSPENDED', NOW() - INTERVAL '1 day');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"SellerProfile\" (id, \"userId\", \"storeName\", bio) VALUES ('$SELLER_ACTIVE', '$USER_ACTIVE', 'Active Store', 'Active bio'), ('$SELLER_SUSPENDED', '$USER_SUSPENDED', 'Suspended Store', 'Suspended bio');"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/sellers")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
ACTIVE_STATUS=$(jq -r --arg id "$SELLER_ACTIVE" '.[] | select(.id == $id) | .status' "$RESPONSE_FILE")
SUSPENDED_STATUS=$(jq -r --arg id "$SELLER_SUSPENDED" '.[] | select(.id == $id) | .status' "$RESPONSE_FILE")
[ "$ACTIVE_STATUS" = "ACTIVE" ]
[ "$SUSPENDED_STATUS" = "SUSPENDED" ]

# Cleanup — undo Given side effects via trap

echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_includes_user_status'
