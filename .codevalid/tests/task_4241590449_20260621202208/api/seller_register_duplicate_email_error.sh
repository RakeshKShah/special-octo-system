#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
EXISTING_EMAIL="existing-${CASE_SUFFIX}@example.com"
RESPONSE_FILE="/tmp/seller_register_duplicate_email_error_${CASE_SUFFIX}.json"
SEED_FILE="/tmp/seller_register_duplicate_email_seed_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM seller_profiles WHERE user_id IN (SELECT id FROM users WHERE email = '${EXISTING_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EXISTING_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$SEED_FILE"
}
trap cleanup EXIT

# Given — create an existing account for the target email using the public registration API.
SEED_STATUS="$(curl -sS -o "$SEED_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EXISTING_EMAIL}\",\"password\":\"Password123!\",\"role\":\"BUYER\"}")"
[ "$SEED_STATUS" = "201" ]

# When — attempt to register again with the same email.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EXISTING_EMAIL}\",\"password\":\"Password123!\",\"role\":\"SELLER\"}")"

# Then — response is 400 with the duplicate email error.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":"Email already registered"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_duplicate_email_error"

# Cleanup — remove seeded user and any related seller profile. Handled by trap.
