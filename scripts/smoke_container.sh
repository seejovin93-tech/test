#!/usr/bin/env bash
set -euo pipefail

# Use exported DOCKER if present; else detect now.
DOCKER_BIN="${DOCKER:-}"
if [[ -z "$DOCKER_BIN" ]]; then
  if docker version >/dev/null 2>&1; then
    DOCKER_BIN="docker"
  else
    DOCKER_BIN="sudo docker"
  fi
fi

name="prufwerk"
img="prufwerk:local"

echo "== start container =="
$DOCKER_BIN rm -f "$name" 2>/dev/null || true
$DOCKER_BIN run -d --name "$name" -p 8080:8080 "$img" >/dev/null

# wait for service
for i in {1..10}; do
  if curl -sf "http://localhost:8080/health" >/dev/null; then break; fi
  sleep 0.5
done

./scripts/smoke.sh

echo "== logs =="
$DOCKER_BIN logs "$name" | tail -n +1

echo "== stop container =="
$DOCKER_BIN rm -f "$name" >/dev/null
echo "CONTAINER SMOKE: PASS"
