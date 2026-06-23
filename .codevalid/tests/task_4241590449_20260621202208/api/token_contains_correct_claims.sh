#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="claims-${CASE_SUFFIX}@example.com"
STORE_NAME="Claims Store ${CASE_SUFFIX}"
BIO="Testing token claims ${CASE_SUFFIX}"
RESPONSE_FILE="/tmp/token_contains_correct_claims_${CASE_SUFFIX}.json"
TOKEN_PAYLOAD_FILE="/tmp/token_contains_correct_claims_payload_${CASE_SUFFIX}.json"

cleanup() {
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true
  rm -f "$RESPONSE_FILE" "$TOKEN_PAYLOAD_FILE"
}
trap cleanup EXIT

# Given — ensure database reachability and no prior rows for this unique seller email.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"SellerProfile\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE email = '${SELLER_EMAIL}');" >/dev/null 2>&1 || true
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM \"User\" WHERE email = '${SELLER_EMAIL}';" >/dev/null 2>&1 || true

# When — register a seller and decode the returned JWT payload without signature verification.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${SELLER_EMAIL}\",\"password\":\"ClaimsPass!23\",\"role\":\"SELLER\",\"storeName\":\"${STORE_NAME}\",\"bio\":\"${BIO}\"}")"
[ "$HTTP_STATUS" = "201" ]
TOKEN="$(jq -r '.token' "$RESPONSE_FILE")"
USER_ID="$(jq -r '.user.id' "$RESPONSE_FILE")"
SELLER_PROFILE_ID="$(jq -r '.user.sellerProfile.id' "$RESPONSE_FILE")"
PAYLOAD_B64="$(printf '%s' "$TOKEN" | cut -d '.' -f2 | tr '_-' '/+')"
PADDED_PAYLOAD="$PAYLOAD_B64"
while [ $(( ${#PADDED_PAYLOAD} % 4 )) -ne 0 ]; do PADDED_PAYLOAD="${PADDED_PAYLOAD}="; done
printf '%s' "$PADDED_PAYLOAD" | base64 -d > "$TOKEN_PAYLOAD_FILE"

# Then — decoded payload claims match the created user response.
[ "$(jq -r '.id' "$TOKEN_PAYLOAD_FILE")" = "$USER_ID" ]
[ "$(jq -r '.email' "$TOKEN_PAYLOAD_FILE")" = "$SELLER_EMAIL" ]
[ "$(jq -r '.role' "$TOKEN_PAYLOAD_FILE")" = "SELLER" ]
[ "$(jq -r '.status' "$TOKEN_PAYLOAD_FILE")" = "PENDING" ]
[ "$(jq -r '.sellerProfileId' "$TOKEN_PAYLOAD_FILE")" = "$SELLER_PROFILE_ID" ]

echo "CODEVALID_TEST_ASSERTION_OK:token_contains_correct_claims"

# Cleanup — remove created seller profile and user. Handled by trap.
