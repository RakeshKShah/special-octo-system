#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
CASE_SUFFIX="$(date +%s)-$$"
RESPONSE_FILE="/tmp/unauthenticated_request_response_${CASE_SUFFIX}.json"

cleanup_files() {
  rm -f "$RESPONSE_FILE"
}
trap cleanup_files EXIT

# Given — no authentication credentials are provided.
: >/dev/null

# When — send POST /orders/:id/ship without Authorization header.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/orders/order-${CASE_SUFFIX}/ship")"

# Then — requireAuth rejects the request.
[ "$HTTP_STATUS" = "401" ]
jq -e '.error == "Unauthorized"' "$RESPONSE_FILE" >/dev/null

# Cleanup — stateless request; no side effects created.
echo "CODEVALID_TEST_ASSERTION_OK:unauthenticated_request"
