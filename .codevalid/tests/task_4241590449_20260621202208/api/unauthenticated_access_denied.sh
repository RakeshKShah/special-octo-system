#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no authenticated session exists
: "case ${CASE_SUFFIX} exercises dashboard without Authorization header"

# When — request the seller dashboard without auth
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X GET "$BASE_URL/dashboard")

# Then — request is rejected by requireAuth middleware
[ "$HTTP_CODE" = "401" ] || { echo "Expected 401 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -E 'error|auth|token|unauth' "$RESPONSE_FILE" >/dev/null || { echo 'Expected authentication error body'; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — stateless case

echo 'CODEVALID_TEST_ASSERTION_OK:unauthenticated_access_denied'
