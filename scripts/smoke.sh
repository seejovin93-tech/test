#!/usr/bin/env bash
set -euo pipefail

base="http://localhost:8080"
LAST_BODY=""

request() {
  local method="$1" url="$2" data="${3:-}" expect="$4" print="${5:-1}"
  url="${url//$'\r'/}"  # sanitize URL
  local tmp; tmp="$(mktemp)"
  local code

  if [[ -n "$data" ]]; then
    code="$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" -H "Content-Type: application/json" -d "$data" "$url")"
  else
    code="$(curl -sS -o "$tmp" -w "%{http_code}" -X "$method" "$url")"
  fi
  LAST_BODY="$(cat "$tmp")"; rm -f "$tmp"

  echo "=== $method $url | expect $expect ==="
  if [[ "$print" -eq 1 ]]; then echo "$LAST_BODY"; fi

  if [[ "$code" != "$expect" ]]; then
    echo "SMOKE: FAIL - $method $url expected $expect, got $code; body: $LAST_BODY"
    exit 1
  fi
}

# Health
request GET   "${base}/health" "" 200

# Pre-list
request GET   "${base}/tasks" "" 200

# Create and capture ID (suppress extra printing)
request POST  "${base}/tasks" '{"text":"demo"}' 201 0
# Try jq first; fallback to sed; take the last match; strip non-digits/newlines
task_id="$( echo "$LAST_BODY" | jq -r '.id' 2>/dev/null || echo "$LAST_BODY" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | tail -n1 )"
task_id="${task_id//[!0-9]/}"

if [[ -z "${task_id:-}" ]]; then
  echo "SMOKE: FAIL - could not extract task id from POST: $LAST_BODY"
  exit 1
fi

# Verify list
request GET   "${base}/tasks" "" 200

# Update created task
request PUT   "${base}/tasks?id=${task_id}" '{"done":true}' 200

# Verify list again
request GET   "${base}/tasks" "" 200

# Allow limiter to refill (defensive)
sleep 0.5

# Delete created task
request DELETE "${base}/tasks?id=${task_id}" "" 200

# Final list
request GET   "${base}/tasks" "" 200

echo "SMOKE: PASS"
