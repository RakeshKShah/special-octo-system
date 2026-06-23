#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="dup-${CASE_SUFFIX}@example.com"
USER_ID="user_${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/duplicate_email_rejection_${CASE_SUFFIX}.json"
BCRYPT_HASH="\$2b\$10\$7aFQZx5lO0xUe4Iu05oH3.PXxN44IVdQydb9h9NP7VDaRao7IhiEC"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — seed an existing user with the target email
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "INSERT INTO \"User\" (id, email, \"passwordHash\", role, status, \"createdAt\", \"updatedAt\") VALUES ('${USER_ID}', '${EMAIL}', '${BCRYPT_HASH}', 'BUYER', 'ACTIVE', NOW(), NOW());" >/dev/null

# When — attempt duplicate registration with same email
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"AnotherPass1!\",\"role\":\"SELLER\"}")"

# Then — assert duplicate-email rejection
[ "$HTTP_STATUS" = "400" ]
jq -e '.error == "Email already registered"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:duplicate_email_rejection"

# Cleanup — handled by trap
