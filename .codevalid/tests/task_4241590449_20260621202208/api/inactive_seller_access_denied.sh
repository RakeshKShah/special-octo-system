#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="pending-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!"
STORE_NAME="Pending Store ${CASE_SUFFIX}"
BIO="Pending seller access check"
REGISTER_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
TOKEN=""

cleanup() {
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register a seller account, which the API sets to PENDING per call graph
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"SELLER\",store_name:\"$STORE_NAME\",\"bio\":\"$BIO\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ] || { echo "Expected 201 got $HTTP_CODE"; cat "$REGISTER_FILE"; exit 1; }
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] || { echo 'Expected token in register response'; cat "$REGISTER_FILE"; exit 1; }
grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null || { echo 'Expected registered seller to be PENDING'; cat "$REGISTER_FILE"; exit 1; }

# When — call the seller dashboard with a non-active seller token
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET -H "Authorization: Bearer $TOKEN" "$BASE_URL/dashboard")

# Then — requireActiveSeller rejects access
[ "$HTTP_CODE" = "403" ] || { echo "Expected 403 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -E 'error|active|seller|forbidden' "$RESPONSE_FILE" >/dev/null || { echo 'Expected authorization error body'; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — no verified public delete endpoint available

echo 'CODEVALID_TEST_ASSERTION_OK:inactive_seller_access_denied'
