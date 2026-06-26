#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"
USER_ALPHA="cv_user_alpha_${CASE_SUFFIX}"
USER_BETA="cv_user_beta_${CASE_SUFFIX}"
USER_GAMMA="cv_user_gamma_${CASE_SUFFIX}"
SELLER_ALPHA="cv_seller_alpha_${CASE_SUFFIX}"
SELLER_BETA="cv_seller_beta_${CASE_SUFFIX}"
SELLER_GAMMA="cv_seller_gamma_${CASE_SUFFIX}"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM products WHERE seller_id IN ('$SELLER_ALPHA', '$SELLER_BETA', '$SELLER_GAMMA');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE id IN ('$SELLER_ALPHA', '$SELLER_BETA', '$SELLER_GAMMA');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id IN ('$USER_ALPHA', '$USER_BETA', '$USER_GAMMA');" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO users (id, email, password_hash, role, status, created_at) VALUES ('$USER_ALPHA', 'alpha-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', TIMESTAMP WITH TIME ZONE '2024-01-01T00:00:00Z'), ('$USER_BETA', 'beta-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', TIMESTAMP WITH TIME ZONE '2024-01-05T00:00:00Z'), ('$USER_GAMMA', 'gamma-${CASE_SUFFIX}@example.com', 'hash', 'SELLER', 'ACTIVE', TIMESTAMP WITH TIME ZONE '2024-01-03T00:00:00Z');"
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO seller_profiles (id, user_id, store_name, bio) VALUES ('$SELLER_ALPHA', '$USER_ALPHA', 'Alpha Store', 'Alpha bio'), ('$SELLER_BETA', '$USER_BETA', 'Beta Store', 'Beta bio'), ('$SELLER_GAMMA', '$USER_GAMMA', 'Gamma Store', 'Gamma bio');"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' "$BASE_URL/admin/sellers")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "200" ]
FIRST_ID=$(jq -r '.[0].id' "$RESPONSE_FILE")
SECOND_ID=$(jq -r '.[1].id' "$RESPONSE_FILE")
THIRD_ID=$(jq -r '.[2].id' "$RESPONSE_FILE")
[ "$FIRST_ID" = "$SELLER_BETA" ]
[ "$SECOND_ID" = "$SELLER_GAMMA" ]
[ "$THIRD_ID" = "$SELLER_ALPHA" ]

# Cleanup — undo Given side effects via trap

echo 'CODEVALID_TEST_ASSERTION_OK:get_sellers_ordered_by_creation_date_desc'
