#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/seller_register_invalid_email_format_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — app is reachable for registration requests.
curl -sS -o /dev/null "$BASE_URL/health"

# When — send a registration payload with invalid email syntax.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/register" \
  -H 'Content-Type: application/json' \
  --data '{"email":"not-an-email","password":"ValidPass789!","role":"SELLER"}')"

# Then — response is 400 and the error references invalid email validation.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null
if grep -F 'Invalid email' "$RESPONSE_FILE" >/dev/null 2>&1; then
  :
else
  grep -i 'email' "$RESPONSE_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_invalid_email_format"

# Cleanup — stateless case; remove temp file only.
