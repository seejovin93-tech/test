#!/usr/bin/env bash
set -euo pipefail

# --- I1 evidence setup (S1 Day 2) ---
I1_EVIDENCE_DIR="evidence/logs/i1"
mkdir -p "${I1_EVIDENCE_DIR}"

RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
I1_EVIDENCE_PATH="${I1_EVIDENCE_DIR}/demo_i1_${RUN_TS}.jsonl"
I1_CORRELATION_ID="demo_i1_${RUN_TS}_$$"

i1_log() {
  local decision="$1"
  local image_ref="$2"
  local step="$3"

  go run ./cmd/i1log \
    -out "${I1_EVIDENCE_PATH}" \
    -correlation_id "${I1_CORRELATION_ID}" \
    -decision "${decision}" \
    -image_ref "${image_ref}" \
    -demo_step "${step}"
}
# --- end I1 evidence setup ---

echo "== Prufwerk Day 7: I1 prototype demo =="
echo

# --- basic sanity: are we in repo root? ---
if [ ! -f "go.mod" ] || [ ! -d "scripts" ] || [ ! -d "k8s" ]; then
  echo "[FATAL] Run this script from the repo root (where go.mod, scripts/, k8s/ exist)."
  exit 1
fi

# Helper to label steps
step() {
  echo
  echo "[STEP] $1"
  echo "----------------------------------------"
}

# 1) Run Day 1–3 tests (Go tests + local + container smoke)
step "Running test_all.sh (Go tests, local smoke, Docker build, container smoke)..."
./scripts/test_all.sh

# 2) Ensure kind cluster exists and kube context is set
CLUSTER_NAME="prufwerk"

step "Ensuring kind cluster '$CLUSTER_NAME' exists..."
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "  - Creating kind cluster '${CLUSTER_NAME}'..."
  kind create cluster --name "${CLUSTER_NAME}" --image kindest/node:v1.28.0
else
  echo "  - kind cluster '${CLUSTER_NAME}' already exists."
fi

echo "  - Using kube context kind-${CLUSTER_NAME}"
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null

# 3) Deploy (or refresh) Prufwerk Deployment + Service
step "Applying k8s/deployment.yaml and k8s/service.yaml..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "  - Waiting for Deployment rollout..."
kubectl rollout status deployment prufwerk

# 4) Install Kyverno if needed
step "Ensuring Kyverno is installed..."
if ! kubectl get ns kyverno >/dev/null 2>&1; then
  echo "  - Installing Kyverno (this may take ~1–2 minutes)..."
  kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml
else
  echo "  - Kyverno namespace already exists."
fi

echo "  - Waiting for Kyverno pods to be Ready..."
kubectl wait --for=condition=Ready pods -n kyverno --all --timeout=180s || {
  echo "[WARN] Some Kyverno cleanup cronjob pods may stay in ImagePullBackOff; core admission pods just need to be Ready."
}

# 5) Apply the require-signed-images-default ClusterPolicy
step "Applying Kyverno ClusterPolicy (require-signed-images-default)..."
kubectl apply -f k8s/kyverno-verify-images.yaml

echo "  - Checking ClusterPolicy status..."
kubectl get cpol require-signed-images-default -o yaml | grep -E 'name: require-signed-images-default|ready:'

# 6) Ensure signed :latest image is running and healthy
SIGNED_IMAGE="docker.io/seejovin93/prufwerk:latest"

step "Confirming signed image (${SIGNED_IMAGE}) is admitted and healthy..."
echo "  - Forcing Deployment image to ${SIGNED_IMAGE}..."
kubectl set image deploy/prufwerk prufwerk="${SIGNED_IMAGE}"

echo "  - Waiting for rollout..."
kubectl rollout status deployment prufwerk

echo "  - Verifying cosign signature for ${SIGNED_IMAGE}..."
cosign verify --key cosign.pub "${SIGNED_IMAGE}"

echo "  - Checking that Deployment spec uses ${SIGNED_IMAGE}..."
CUR_IMAGE="$(kubectl get deploy prufwerk -o=jsonpath='{.spec.template.spec.containers[0].image}')"
echo "    Deployment image: ${CUR_IMAGE}"
if [[ "${CUR_IMAGE}" != "${SIGNED_IMAGE}" ]]; then
  echo "[FATAL] Expected Deployment image ${SIGNED_IMAGE}, got ${CUR_IMAGE}"
  exit 1
fi

# Optional: quick external smoke via port-forward + smoke.sh
step "Running smoke.sh against the cluster via port-forward..."
kubectl port-forward deploy/prufwerk 8080:8080 >/tmp/prufwerk-pf.log 2>&1 &
PF_PID=$!

# Wait for port-forward to become usable (simple retry loop)
MAX_TRIES=10
READY=0
for i in $(seq 1 "${MAX_TRIES}"); do
  if curl -sSf http://localhost:8080/health >/dev/null 2>&1; then
    echo "  - Port-forward is ready (attempt ${i})."
    READY=1
    break
  fi
  echo "  - Waiting for port-forward to be ready (attempt ${i})..."
  sleep 1
done

if [[ "${READY}" -ne 1 ]]; then
  echo "[FATAL] Port-forward to prufwerk never became ready on :8080 after ${MAX_TRIES} attempts."
  kill "${PF_PID}" 2>/dev/null || true
  wait "${PF_PID}" 2>/dev/null || true
  exit 1
fi

./scripts/smoke.sh || {
  echo "[FATAL] smoke.sh failed against port-forwarded deployment"
  kill "${PF_PID}" 2>/dev/null || true
  wait "${PF_PID}" 2>/dev/null || true
  exit 1
}

kill "${PF_PID}" 2>/dev/null || true
wait "${PF_PID}" 2>/dev/null || true

# Log I1 evidence: signed path allowed
i1_log "ALLOW" "${SIGNED_IMAGE}" "C6_SIGNED_PATH"

# 7) Build and push a NEW unsigned image (fresh digest)
UNSIGNED_TAG="unsigned-$(date -u +%Y%m%d%H%M%S)"
UNSIGNED_IMAGE="docker.io/seejovin93/prufwerk:${UNSIGNED_TAG}"

step "Building and pushing UNSIGNED image (new digest: ${UNSIGNED_IMAGE})..."
docker build --no-cache --label "build-id=${UNSIGNED_TAG}" -t "${UNSIGNED_IMAGE}" .
docker push "${UNSIGNED_IMAGE}"

echo "  - Verifying cosign verify FAILS for ${UNSIGNED_IMAGE} (expected)..."
if cosign verify --key cosign.pub "${UNSIGNED_IMAGE}"; then
  echo "[FATAL] cosign unexpectedly succeeded on unsigned image ${UNSIGNED_IMAGE}"
  exit 1
else
  echo "  - As expected, cosign verify FAILED for ${UNSIGNED_IMAGE}"
fi

# 8) Attempt to roll out UNSIGNED image and expect Kyverno DENY
step "Attempting to roll out UNSIGNED image (expect Kyverno DENY)..."
set +e
KUBECTL_OUT="$(kubectl set image deploy/prufwerk prufwerk=${UNSIGNED_IMAGE} 2>&1)"
SET_RC=$?
set -e

echo "${KUBECTL_OUT}"
if [ "${SET_RC}" -eq 0 ]; then
  echo "[FATAL] kubectl set image succeeded; unsigned image was admitted, which violates I1."
  exit 1
fi

echo
echo "  - kubectl set image exit code: ${SET_RC} (non-zero as expected)"
echo "  - Checking recent events mentioning prufwerk / Kyverno..."
kubectl get events -A --sort-by=.lastTimestamp | tail -n 30 | grep -Ei 'prufwerk|Kyverno|kyverno' || true

# Log I1 evidence: unsigned path denied
i1_log "DENY" "${UNSIGNED_IMAGE}" "C7_UNSIGNED_PATH"

# 9) Confirm Deployment still on signed :latest
step "Confirming Deployment is STILL on signed image (${SIGNED_IMAGE})..."
CUR_IMAGE_AFTER="$(kubectl get deploy prufwerk -o=jsonpath='{.spec.template.spec.containers[0].image}')"
echo "    Deployment image after unsigned attempt: ${CUR_IMAGE_AFTER}"
if [[ "${CUR_IMAGE_AFTER}" != "${SIGNED_IMAGE}" ]]; then
  echo "[FATAL] Expected Deployment to remain on ${SIGNED_IMAGE} after Kyverno DENY, got ${CUR_IMAGE_AFTER}"
  exit 1
fi

echo
echo "============================================================"
echo "I1 demo SUCCESS: 'no valid signature / no provenance → no run'"
echo "  - Signed image ${SIGNED_IMAGE} admitted and running."
echo "  - Unsigned image ${UNSIGNED_IMAGE} blocked by Kyverno (no matching signatures)."
echo "  - Deployment still uses signed image."
echo "============================================================"

echo
echo "[I1] Evidence written to: ${I1_EVIDENCE_PATH}"
echo "[I1] Correlation ID: ${I1_CORRELATION_ID}"

# 10) S1B — Ship evidence JSONL to WORM bucket
step "S1B: Shipping I1 evidence JSONL to WORM bucket..."
./scripts/ship_i1_evidence.sh "${I1_EVIDENCE_PATH}" || {
  echo "[FATAL] WORM upload failed; local evidence remains at ${I1_EVIDENCE_PATH}"
  exit 1
}

echo
echo "[S1B] Evidence successfully pinned to WORM (S3 bucket: prufwerk-i1-evidence-worm)"
