#!/usr/bin/env bash
set -euo pipefail
base="http://localhost:8080"

echo "Bursting 15 requests to /health (should see some 429)..."
seq 1 15 | xargs -I{} -P15 curl -s -o /dev/null -w "%{http_code}\n" "$base/health" \
  | sort | uniq -c
