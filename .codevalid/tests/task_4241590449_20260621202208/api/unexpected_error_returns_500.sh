#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TOXIPROXY_API_URL="${TOXIPROXY_API_URL:-http://toxiproxy:8474}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="error-${CASE_SUFFIX}@example.com"
PASSWORD="Password123!Aa"
STORE_NAME="Store-${CASE_SUFFIX}"
BIO="Bio-${CASE_SUFFIX}"
TOXIC_NAME="db_reset_${CASE_SUFFIX}"
RESPONSE_FILE="$(mktemp)"
REGISTER_FILE="$(mktemp)"
TOXIC_FILE="$(mktemp)"
TOKEN=""
TOXIC_CREATED="0"

cleanup() {
  if [ "$TOXIC_CREATED" = "1" ]; then
    curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$TOXIPROXY_API_URL/proxies/postgres/toxics/$TOXIC_NAME" >/dev/null 2>&1 || true
  fi
  rm -f "$RESPONSE_FILE" "$REGISTER_FILE" "$TOXIC_FILE"
}
trap cleanup EXIT

# Given — bring the system to the required state
HTTP_CODE=$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"role\":\"SELLER\",store_name:\"$STORE_NAME\",\"bio\":\"$BIO\"}" "$BASE_URL/auth/register")
[ "$HTTP_CODE" = "201" ]
TOKEN=$(jq -r '.token' "$REGISTER_FILE")
[ -n "$TOKEN" ]
[ "$TOKEN" != "null" ]
if grep -F '"status":"PENDING"' "$REGISTER_FILE" >/dev/null 2>&1; then
  echo 'seller registered as PENDING; 500 case requires an active seller token in this environment' >&2
  cat "$REGISTER_FILE" >&2
  exit 1
fi
HTTP_CODE=$(curl -sS -o "$TOXIC_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"name\":\"$TOXIC_NAME\",\"type\":\"reset_peer\",\"stream\":\"downstream\",\"toxicity\":1.0,\"attributes\":{}}" "$TOXIPROXY_API_URL/proxies/postgres/toxics")
[ "$HTTP_CODE" = "200" ]
TOXIC_CREATED="1"

# When — perform the action under test
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" -d "{\"title\":\"Failure Product ${CASE_SUFFIX}\",\"description\":\"desc\",\"category\":\"HOME\",\"price_cents\":1200,\"stock_qty\":1,\"photos\":[]}" "$BASE_URL/products")

# Then — HTTP/body assertions
[ "$HTTP_CODE" = "500" ]
grep -F 'Failed to create product' "$RESPONSE_FILE" >/dev/null

# Cleanup — undo Given side effects
# toxic removed in trap

echo 'CODEVALID_TEST_ASSERTION_OK:unexpected_error_returns_500'
