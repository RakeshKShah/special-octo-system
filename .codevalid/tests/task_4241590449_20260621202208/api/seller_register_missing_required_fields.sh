#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/seller_register_missing_required_fields_${CASE_SUFFIX}.json"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — app is reachable for registration requests.
curl -sS -o /dev/null "$BASE_URL/health"

# When — send an empty JSON payload to /register.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data '{}')"

# Then — response is 400 and contains an error field for validation failure.
[ "$HTTP_STATUS" = "400" ]
grep -F '"error":' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:seller_register_missing_required_fields"

# Cleanup — stateless case; remove temp file only.
