#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="$(mktemp)"

cleanup() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — no specific setup required

# When — submit an empty registration payload
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{}" "$BASE_URL/register")

# Then — assert validation failure is returned
[ "$HTTP_CODE" = "400" ]
grep -F '"error"' "$RESPONSE_FILE" >/dev/null
if grep -Ei 'email|password|required|invalid' "$RESPONSE_FILE" >/dev/null; then :; else cat "$RESPONSE_FILE"; exit 1; fi

# Cleanup — stateless request only

echo 'CODEVALID_TEST_ASSERTION_OK:missing_required_fields'
