#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
TOXIPROXY_URL="${TOXIPROXY_URL:-http://toxiproxy:8474}"
CASE_SUFFIX="$(date +%s)-$$"
SELLER_EMAIL="seller_db_error_${CASE_SUFFIX}@example.com"
SELLER_PASSWORD="Password123!"
REGISTER_FILE="/tmp/product_create_db_error_returns_500_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/product_create_db_error_returns_500_${CASE_SUFFIX}.json"
TOXIC_NAME="cut_write_${CASE_SUFFIX}"
TOXIC_CREATED=0

cleanup() {
  if [ "$TOXIC_CREATED" = "1" ]; then
    curl -sS -X DELETE "$TOXIPROXY_URL/proxies/postgres/toxics/${TOXIC_NAME}" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — Register a seller and inject a postgres timeout toxic through toxiproxy.
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/register" \n  -H 'Content-Type: application/json' \n  --data "{"email":"${SELLER_EMAIL}","password":"${SELLER_PASSWORD}","role":"SELLER","storeName":"DB Error Store ${CASE_SUFFIX}","bio":"Failure injection"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(grep -o '"token":"[^"]*"' "$REGISTER_FILE" | head -1 | cut -d'"' -f4)"
[ -n "$TOKEN" ]
curl -sS "$TOXIPROXY_URL/version" >/dev/null
curl -sS -X POST "$TOXIPROXY_URL/proxies/postgres/toxics" \n  -H 'Content-Type: application/json' \n  --data "{"name":"${TOXIC_NAME}","type":"timeout","stream":"downstream","toxicity":1.0,"attributes":{"timeout":5000}}" >/dev/null
TOXIC_CREATED=1

# When — POST /products with valid data while the database path is disrupted.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \n  -X POST "$BASE_URL/products" \n  -H 'Content-Type: application/json' \n  -H "Authorization: Bearer ${TOKEN}" \n  --data "{"title":"DB Failure Product ${CASE_SUFFIX}","description":"Should fail","category":"MISC","price_cents":1900,"stock_qty":2,"photos":[]}")"

# Then — Expect HTTP 500 generic create failure.
[ "$HTTP_STATUS" = "500" ]
grep -F '"error":"Failed to create product"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:product_create_db_error_returns_500"

# Cleanup — Remove toxiproxy toxic and temporary files via trap.
