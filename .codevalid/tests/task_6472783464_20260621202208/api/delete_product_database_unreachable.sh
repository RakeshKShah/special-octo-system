#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TOXIPROXY_URL="${TOXIPROXY_URL:-http://toxiproxy:8474}"
SELLER_TOKEN="${SELLER_TOKEN:-seller-42-token}"
PRODUCT_ID="${PRODUCT_ID:-prod-107}"
CASE_SUFFIX="$(date +%s)-$$"
TOXIC_NAME="db_timeout_${CASE_SUFFIX}"
CREATE_FILE="$(mktemp)"
RESPONSE_FILE="$(mktemp)"
DELETE_FILE="$(mktemp)"

cleanup() {
  curl -sS -o "$DELETE_FILE" -w '%{http_code}' -X DELETE "$TOXIPROXY_URL/proxies/postgres/toxics/$TOXIC_NAME" >/dev/null 2>&1 || true
  rm -f "$CREATE_FILE" "$RESPONSE_FILE" "$DELETE_FILE"
}
trap cleanup EXIT

# Given — simulate database unavailability through toxiproxy
CREATE_CODE=$(curl -sS -o "$CREATE_FILE" -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d "{\"name\":\"$TOXIC_NAME\",\"type\":\"timeout\",\"stream\":\"downstream\",\"attributes\":{\"timeout\":1000}}" "$TOXIPROXY_URL/proxies/postgres/toxics")
case "$CREATE_CODE" in
  200|201) ;;
  *) echo "Failed to create postgres toxic, got $CREATE_CODE"; cat "$CREATE_FILE"; exit 1 ;;
esac
AUTH_HEADER="Authorization: Bearer $SELLER_TOKEN"

# When — seller attempts product deletion during DB outage
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' -X DELETE -H "$AUTH_HEADER" "$BASE_URL/products/$PRODUCT_ID")

# Then — server returns a graceful failure instead of crashing
[ "$HTTP_CODE" = "500" ] || { echo "Expected 500 got $HTTP_CODE"; cat "$RESPONSE_FILE"; exit 1; }
grep -E 'error|failed|internal' "$RESPONSE_FILE" >/dev/null || { echo "Expected server error payload"; cat "$RESPONSE_FILE"; exit 1; }

# Cleanup — remove toxiproxy toxic via trap

echo 'CODEVALID_TEST_ASSERTION_OK:delete_product_database_unreachable'
