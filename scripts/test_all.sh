#!/usr/bin/env bash
set -euo pipefail

# Prefer regular docker; fallback to sudo docker if this shell lacks access.
if docker version >/dev/null 2>&1; then
  DOCKER="docker"
else
  DOCKER="sudo docker"
fi
export DOCKER

free_port_8080() {
  # kill any local process bound to :8080
  (command -v fuser >/dev/null 2>&1 && sudo fuser -k 8080/tcp >/dev/null 2>&1) || true
  (command -v lsof  >/dev/null 2>&1 && lsof -ti :8080 | xargs -r kill -9) || true
  # stop any container mapping 8080
  $DOCKER ps --format '{{.ID}} {{.Ports}}' | awk '/:8080->/ {print $1}' | xargs -r $DOCKER rm -f >/dev/null 2>&1 || true
}

echo "== Go format/vet/test =="
go fmt ./...
go vet ./...
go clean -testcache
go test -v ./...

echo "== Run local server (background) =="
free_port_8080
pkill -f "go run" 2>/dev/null || true
(go run . >/tmp/prufwerk.out 2>&1) &
srv_pid=$!

# wait for server to come up
for i in {1..20}; do
  if curl -sf http://localhost:8080/health >/dev/null; then break; fi
  sleep 0.25
done

echo "== Local smoke =="
./scripts/smoke.sh

echo "== Kill local server =="
kill "$srv_pid" 2>/dev/null || true
wait "$srv_pid" 2>/dev/null || true
free_port_8080

echo "== Docker build (Day 3) =="
$DOCKER build -t prufwerk:local .

echo "== Container smoke =="
./scripts/smoke_container.sh

echo "ALL TESTS: PASS"
