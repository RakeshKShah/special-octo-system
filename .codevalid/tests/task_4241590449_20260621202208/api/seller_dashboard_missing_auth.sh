#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="seller_dashboard_missing_auth_$(date +%s)_$$"
RESP_FILE="/tmp/${CASE_SUFFIX}_resp.json"
trap 'rm -f "$RESP_FILE"' EXIT

# Given — no authentication is provided.
:

# When — fetch seller dashboard without Authorization header.
status="$(curl -sS -o "$RESP_FILE" -w '%{http_code}' -X GET "$BASE_URL/seller/dashboard")"

# Then — request is rejected by requireAuth.
[ "$status" = "401" ]
if command -v jq >/dev/null 2>&1; then
  [ "$(jq -r '.error' "$RESP_FILE")" = "Unauthorized" ]
else
  grep -F 'Unauthorized' "$RESP_FILE" >/dev/null
fi

echo "CODEVALID_TEST_ASSERTION_OK:seller_dashboard_missing_auth"

# Cleanup — stateless, nothing to undo.
