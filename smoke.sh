#!/bin/bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
TMP_OUT="$(mktemp)"
cleanup() { rm -f "$TMP_OUT"; }
trap cleanup EXIT

fail() {
  echo "SMOKE: FAIL - $*"
  exit 1
}

check_http() {
  local expected="$1" url="$2" method="${3:-GET}" data="${4:-}"
  local code
  if [[ -n "$data" ]]; then
    code="$(curl -sS -o "$TMP_OUT" -w "%{http_code}" -X "$method" \
      -H "Content-Type: application/json" -d "$data" "$url")"
  else
    code="$(curl -sS -o "$TMP_OUT" -w "%{http_code}" -X "$method" "$url")"
  fi
  echo ">>> $method $url -> $code"
  [[ "$code" == "$expected" ]] || fail "$method $url expected $expected, got $code; body: $(cat "$TMP_OUT")"
}

echo "=== HEALTH ==="
check_http 200 "$BASE_URL/health"

echo "=== GET (pre) ==="
check_http 200 "$BASE_URL/tasks" GET

echo "=== POST ==="
check_http 201 "$BASE_URL/tasks" POST '{"text":"demo"}'

echo "=== GET (after POST) ==="
check_http 200 "$BASE_URL/tasks" GET

echo "=== PUT ==="
check_http 200 "$BASE_URL/tasks?id=1" PUT '{"done":true}'

echo "=== GET (after PUT) ==="
check_http 200 "$BASE_URL/tasks" GET

echo "=== DELETE ==="
check_http 200 "$BASE_URL/tasks?id=1" DELETE

echo "=== GET (final) ==="
final_body="$(curl -sS "$BASE_URL/tasks")"
echo "body: $final_body"
# Expect an empty JSON array (allowing for whitespace/newline)
if [[ ! "$final_body" =~ ^[[:space:]]*\[[[:space:]]*\][[:space:]]*$ ]]; then
  fail "expected empty list after delete"
fi

echo "SMOKE: PASS"
