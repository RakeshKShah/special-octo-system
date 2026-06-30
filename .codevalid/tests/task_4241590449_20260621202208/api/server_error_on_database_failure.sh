#!/usr/bin/env sh
set -eu

BASE_URL="${BASE_URL:-http://app:6713}"
DATABASE_URL="${DATABASE_URL:-postgresql://app:app@toxiproxy:5432/appdb}"
TOXIPROXY_URL="${TOXIPROXY_URL:-http://toxiproxy:8474}"
CASE_SUFFIX="$(date +%s)-$$"
EMAIL="db-failure-seller-${CASE_SUFFIX}@example.com"
PASSWORD="Passw0rd!${CASE_SUFFIX}"
STORE_NAME="DB Failure Shop ${CASE_SUFFIX}"
TITLE="Failure Product ${CASE_SUFFIX}"
REGISTER_FILE="/tmp/server_error_on_database_failure_register_${CASE_SUFFIX}.json"
RESPONSE_FILE="/tmp/server_error_on_database_failure_${CASE_SUFFIX}.json"
USER_ID=""
TOKEN=""
TOXIC_NAME="reset-db-${CASE_SUFFIX}"

cleanup() {
  curl -sS -X DELETE "$TOXIPROXY_URL/proxies/postgres/toxics/${TOXIC_NAME}" >/dev/null 2>&1 || true
  if [ -n "$USER_ID" ]; then
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE id = '${USER_ID}';" >/dev/null 2>&1 || true
  else
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "DELETE FROM users WHERE email = '${EMAIL}';" >/dev/null 2>&1 || true
  fi
  rm -f "$REGISTER_FILE" "$RESPONSE_FILE"
}
trap cleanup EXIT

# Given — register and activate a unique seller, then inject a postgres connectivity failure through toxiproxy.
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null
REGISTER_STATUS="$(curl -sS -o "$REGISTER_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/auth/register" \
  -H 'Content-Type: application/json' \
  --data "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\",\"role\":\"SELLER\",store_name:\"${STORE_NAME}\",\"bio\":\"db failure\"}")"
[ "$REGISTER_STATUS" = "201" ]
TOKEN="$(sed -n 's/.*"token":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
USER_ID="$(sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' "$REGISTER_FILE" | head -n 1)"
[ -n "$TOKEN" ]
[ -n "$USER_ID" ]
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "UPDATE users SET status = 'ACTIVE' WHERE id = '${USER_ID}';" >/dev/null
curl -sS -X POST "$TOXIPROXY_URL/proxies/postgres/toxics" \
  -H 'Content-Type: application/json' \
  --data "{\"name\":\"${TOXIC_NAME}\",\"type\":\"reset_peer\",\"stream\":\"downstream\",\"attributes\":{}}" >/dev/null

# When — attempt to create a product while the database connection is being reset.
HTTP_STATUS="$(curl -sS -o "$RESPONSE_FILE" -w '%{http_code}' \
  -X POST "$BASE_URL/products" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${TOKEN}" \
  --data "{\"title\":\"${TITLE}\",\"description\":\"Test\",\"category\":\"Misc\",\"price_cents\":1000,\"stock_qty\":1,\"photos\":[]}")"

# Then — response is 500 with the generic product creation failure error.
[ "$HTTP_STATUS" = "500" ]
grep -F '"error":"Failed to create product"' "$RESPONSE_FILE" >/dev/null

echo "CODEVALID_TEST_ASSERTION_OK:server_error_on_database_failure"

# Cleanup — remove the toxiproxy toxic and delete the created seller account.
