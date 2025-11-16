#!/usr/bin/env bash
set -euo pipefail

EVIDENCE_DIR="evidence/logs/i1"

FILE="${1:-}"

if [[ -z "${FILE}" ]]; then
  if ! ls "${EVIDENCE_DIR}"/demo_i1_*.jsonl >/dev/null 2>&1; then
    echo "[I1 verify] No evidence files found in ${EVIDENCE_DIR}"
    exit 1
  fi

  # pick latest by modification time (newest run)
  FILE="$(ls -1t "${EVIDENCE_DIR}"/demo_i1_*.jsonl 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "${FILE}" || ! -f "${FILE}" ]]; then
  echo "[I1 verify] Evidence file not found: ${FILE}"
  exit 1
fi

echo "[I1 verify] Using evidence file: ${FILE}"

TOTAL_EVENTS="$(jq -s 'length' "${FILE}")"
echo "[I1 verify] Total events: ${TOTAL_EVENTS}"

SIGNED_IMAGE="docker.io/seejovin93/prufwerk:latest"

ALLOW_SIGNED="$(
  jq -s --arg img "${SIGNED_IMAGE}" '
    [ .[] | select(.decision == "ALLOW" and .image_ref == $img) ] | length
  ' "${FILE}"
)"
echo "[I1 verify] ALLOW for signed image (${SIGNED_IMAGE}): ${ALLOW_SIGNED}"

ALLOW_UNSIGNED="$(
  jq -s '
    [ .[] | select(.decision == "ALLOW" and (.image_ref | tostring | contains("unsigned-"))) ] | length
  ' "${FILE}"
)"
echo "[I1 verify] ALLOW events for unsigned-* images (should be 0): ${ALLOW_UNSIGNED}"

DENY_UNSIGNED="$(
  jq -s '
    [ .[] | select(.decision == "DENY" and (.image_ref | tostring | contains("unsigned-"))) ] | length
  ' "${FILE}"
)"
echo "[I1 verify] DENY events for unsigned-* images: ${DENY_UNSIGNED}"

CORR_UNIQUE="$(
  jq -s '
    [ .[].correlation_id ] | unique | length
  ' "${FILE}"
)"
echo "[I1 verify] Unique correlation_id count (non-fatal check): ${CORR_UNIQUE}"

# Behavioural I1 checks
if [[ "${ALLOW_SIGNED}" -lt 1 ]]; then
  echo "[FAIL] No ALLOW event found for signed image ${SIGNED_IMAGE}."
  exit 1
fi

if [[ "${ALLOW_UNSIGNED}" -ne 0 ]]; then
  echo "[FAIL] Found ${ALLOW_UNSIGNED} ALLOW event(s) for unsigned-* images. Violates I1."
  exit 1
fi

if [[ "${DENY_UNSIGNED}" -lt 1 ]]; then
  echo "[FAIL] Expected at least one DENY for unsigned-* image, found ${DENY_UNSIGNED}."
  exit 1
fi

echo "[I1 hash-chain] Verifying hash chain integrity..."
go run ./cmd/i1chaincheck -file "${FILE}"

echo "[PASS] I1 verification succeeded for evidence file: ${FILE}"

