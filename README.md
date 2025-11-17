# Prufwerk — I₁ Prototype (Kyverno + cosign)

Prufwerk is a small, focused prototype that proves a concrete security invariant on Kubernetes:

> **Invariant I₁ — *“no valid signature / no provenance → no run”***
> For the `prufwerk` Deployment: a signed image is admitted and runs; a fresh unsigned image is blocked at admission and **cannot** replace it.

The prototype uses:

* **Kyverno** as an admission controller (`require-signed-images-default` policy),
* **Sigstore cosign** for image signatures and verification,
* **kind** for a local Kubernetes cluster,
* a minimal **Go HTTP API** as the workload.

On top of I₁, slice **S₁** adds a small **evidence spine**:

* every admission decision we care about (signed vs unsigned path) is logged as JSONL with a per-file **hash chain**, and
* a verifier CLI checks that the evidence file matches the I₁ story (ALLOW for signed, DENY for unsigned, hash chain intact).

Slice **S₁B** then pins each evidence file into a **WORM-capable S3 bucket**:

* evidence files are uploaded to `s3://prufwerk-i1-evidence-worm/i1/...`, and
* the evidence writer is prevented from deleting existing evidence objects.

---

## I₁ demo: “no valid signature / no provenance → no run”

### What the demo shows

For the `prufwerk` Deployment:

* A **signed** image (`docker.io/seejovin93/prufwerk:latest`) is:

  * validated with `cosign verify`,
  * admitted by Kyverno (`require-signed-images-default`),
  * rolled out in the cluster,
  * reachable via the `prufwerk` Service.

* A **fresh unsigned** image (`docker.io/seejovin93/prufwerk:unsigned-YYYYMMDDHHMMSS`) is:

  * missing valid cosign signatures,
  * **rejected** by Kyverno’s `require-signed-images-default` ClusterPolicy,
  * **cannot** replace the running signed image in the Deployment.

S₁ then:

* logs these decisions into `evidence/logs/i1/*.jsonl` with a per-file hash chain, and
* verifies the file with a dedicated CLI.

S₁B:

* uploads each evidence file to a WORM-capable S3 bucket:

  * Bucket: `prufwerk-i1-evidence-worm`
  * Prefix: `i1/`
  * Key shape: `i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl`

---

## How to run the I₁ demo

All commands are run from the repository root (where `go.mod`, `scripts/`, `k8s/` live).

### 1. One-shot demo script

This script does **everything** for the I₁ demo:

```bash
./scripts/demo_i1.sh
```

At a high level it:

1. **Runs local tests and container smoke**

   * `go test ./...`
   * local HTTP smoke against `http://localhost:8080`
   * Docker build + container smoke.

2. **Prepares the cluster**

   * ensures a kind cluster named `prufwerk` exists,
   * switches kube-context to `kind-prufwerk`,
   * applies `k8s/deployment.yaml` and `k8s/service.yaml`.

3. **Ensures Kyverno + policy**

   * ensures Kyverno is installed and its **admission pods** are Ready,
   * applies `k8s/kyverno-verify-images.yaml` (ClusterPolicy: `require-signed-images-default`).

4. **Signed path (`C6_SIGNED_PATH` — ALLOW)**

   * forces the Deployment to use the signed image
     `docker.io/seejovin93/prufwerk:latest`,

   * verifies the cosign signature with:

     ```bash
     cosign verify --key cosign.pub docker.io/seejovin93/prufwerk:latest
     ```

   * waits for the Deployment rollout to complete,

   * runs `scripts/smoke.sh` via `kubectl port-forward` to confirm the service is reachable and healthy,

   * calls the `i1log` CLI to append an **ALLOW** event for step `C6_SIGNED_PATH`
     into an evidence file under `evidence/logs/i1/`.

5. **Unsigned path (`C7_UNSIGNED_PATH` — DENY)**

   * builds and pushes a fresh unsigned image with a unique tag, e.g.:

     ```bash
     docker.io/seejovin93/prufwerk:unsigned-YYYYMMDDHHMMSS
     ```

   * confirms `cosign verify` fails for that unsigned tag (no signatures),

   * attempts to roll out the unsigned image with:

     ```bash
     kubectl set image deploy/prufwerk prufwerk=<unsigned-tag>
     ```

   * Kyverno denies the admission (a `PolicyViolation` referencing `require-signed-images-default`),

   * calls the `i1log` CLI again to append a **DENY** event for step `C7_UNSIGNED_PATH`
     into the **same** evidence file.

6. **Summary + evidence locations**

   At the end, the script prints:

   * a final summary that:

     * the signed image was admitted and is running, and
     * the unsigned image was blocked and did **not** replace the signed one;
   * the path to the local evidence file and the correlation ID used.

   Example tail output (shape only):

   ```text
   [I1] Evidence written to: evidence/logs/i1/demo_i1_20251116T074533Z.jsonl
   [I1] Correlation ID: demo_i1_20251116T074533Z_61884
   [S1B] Evidence successfully pinned to WORM (S3 bucket: prufwerk-i1-evidence-worm)
   ```

One run of `demo_i1.sh` → **one evidence file** that contains the ALLOW + DENY story for I₁, stored locally and uploaded to S3.

For more detail, see:
`docs/evidence_i1_walkthrough.md`

---

## How to verify the I₁ evidence (local file)

Pick the evidence file printed by `demo_i1.sh` (pattern:
`evidence/logs/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl`) and run:

```bash
go run ./cmd/i1chaincheck \
  -file evidence/logs/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl
```

The verifier checks that:

* there is **at least one** `ALLOW` event for `docker.io/seejovin93/prufwerk:latest`,
* there are **no** `ALLOW` events for `docker.io/seejovin93/prufwerk:unsigned-*`,
* there is **at least one** `DENY` event for `docker.io/seejovin93/prufwerk:unsigned-*`,
* the **hash chain** over all events in the file is valid.

On success, you see a summary like:

```text
[I1 verify] Total events: 2
[I1 verify] ALLOW for signed image (docker.io/seejovin93/prufwerk:latest): 1
[I1 verify] ALLOW events for unsigned-* images (should be 0): 0
[I1 verify] DENY events for unsigned-* images: 1
[I1 verify] Unique correlation_id count (non-fatal check): 1
[I1 hash-chain] Verifying hash chain integrity...
[I1 hash-chain] OK: 2 event(s) verified
[PASS] I1 verification succeeded for evidence file: evidence/logs/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl
```

This confirms that the **local evidence file** matches the I₁ invariant:

* signed image → admitted (`ALLOW`),
* unsigned image → blocked (`DENY`),
* all events are consistent under a hash chain (no tampering detected).

---

## How to verify the I₁ evidence from S3 (S₁B)

An auditor can also verify evidence **directly from the WORM S3 bucket**.

1. List evidence files:

   ```bash
   aws s3 ls s3://prufwerk-i1-evidence-worm/i1/ \
     --profile prufwerk-evidence-writer
   ```

   Example output (shape):

   ```text
   2025-11-17 11:27:36          7 demo_i1_20251116T162340Z.jsonl
   ```

2. Download a specific evidence file:

   ```bash
   aws s3 cp \
     s3://prufwerk-i1-evidence-worm/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl \
     /tmp/evidence_from_s3.jsonl \
     --profile prufwerk-evidence-writer
   ```

3. Run the verifier:

   ```bash
   go run ./cmd/i1chaincheck \
     -file /tmp/evidence_from_s3.jsonl
   ```

On success, you’ll see the same hash-chain and semantic checks as for a local file:

```text
[I1 hash-chain] OK: 2 event(s) verified
```

This demonstrates that evidence pinned to S3 can be independently verified, and that the S₁B WORM path (demo → JSONL → S3 → verifier) is working as intended.
