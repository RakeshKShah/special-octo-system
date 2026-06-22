#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="seller6-${CASE_SUFFIX}@example.com"
PLAINTEXT_PASSWORD="PlainPassword123"
RESPONSE_FILE="/tmp/register_password_hashed_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — ensure unique seller email is absent
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null

# When — register seller with plaintext password input
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PLAINTEXT_PASSWORD}\",\"role\":\"SELLER\"}")"

# Then — response is 201 and DB passwordHash is not plaintext and looks bcrypt-hashed
[ "$HTTP_STATUS" = "201" ]
PASSWORD_HASH="$(psql "$DATABASE_URL" -t -A -v ON_ERROR_STOP=1 -c "SELECT \"passwordHash\" FROM \"User\" WHERE email = '${EMAIL}' LIMIT 1;")"
[ -n "$PASSWORD_HASH" ]
[ "$PASSWORD_HASH" != "$PLAINTEXT_PASSWORD" ]
printf '%s' "$PASSWORD_HASH" | grep -E '^\$2[aby]\$' >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:register_password_hashed"

# Cleanup — remove created rows
