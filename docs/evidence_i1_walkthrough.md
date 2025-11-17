# I₁ Evidence Walkthrough (S1)

## 1. What this demo proves

**Invariant (I₁).** For the `prufwerk` Deployment in Kubernetes:

> **No valid signature / no provenance → no run.**
> Signed image is admitted and runs. Unsigned image is blocked at admission and cannot replace it.

Concretely, this demo shows:

* A **signed** image (`docker.io/seejovin93/prufwerk:latest`) is:

  * validated with `cosign verify`,
  * admitted by Kyverno (`require-signed-images-default`),
  * rolled out in the cluster,
  * reachable through the `prufwerk` Service.

* A **fresh unsigned** image (`docker.io/seejovin93/prufwerk:unsigned-YYYYMMDDHHMMSS`) is:

  * missing valid cosign signatures,
  * **rejected** by Kyverno’s `require-signed-images-default` ClusterPolicy,
  * **cannot** replace the running signed image in the Deployment.

Slice **S₁** adds a small **evidence spine** on top of I₁:

* every signed/unsigned admission decision is logged into a JSONL file with a **hash chain**, and
* a verifier checks that the evidence file matches the I₁ story (ALLOW for signed, DENY for unsigned, no broken chain).

Slice **S₁B** then pins that JSONL evidence into a **WORM-capable S3 bucket** so that:

* evidence is uploaded to `s3://prufwerk-i1-evidence-worm/i1/...`, and
* a normal writer cannot delete existing evidence objects.

---

## 2. How to run the I₁ demo

All commands below are run from the **repository root** (where `go.mod`, `scripts/`, `k8s/` live).

### 2.1 One-shot demo script

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
   * applies `k8s/kyverno-verify-images.yaml` (ClusterPolicy name: `require-signed-images-default`).

4. **Signed path (`C6_SIGNED_PATH` — ALLOW)**

   * forces the Deployment to use the signed image
     `docker.io/seejovin93/prufwerk:latest`,

   * verifies the cosign signature with

     ```bash
     cosign verify --key cosign.pub docker.io/seejovin93/prufwerk:latest
     ```

   * waits for the Deployment rollout to complete,

   * runs `scripts/smoke.sh` via `kubectl port-forward` to confirm the service is reachable and healthy,

   * calls the `i1log` CLI to append an **ALLOW** event for step `C6_SIGNED_PATH` into an evidence file under `evidence/logs/i1/`.

5. **Unsigned path (`C7_UNSIGNED_PATH` — DENY)**

   * builds and pushes a fresh unsigned image with a unique tag, e.g.

     ```bash
     docker.io/seejovin93/prufwerk:unsigned-YYYYMMDDHHMMSS
     ```

   * confirms `cosign verify` fails for that unsigned tag (no signatures),

   * attempts to roll out the unsigned image with

     ```bash
     kubectl set image deploy/prufwerk prufwerk=<unsigned-tag>
     ```

   * Kyverno denies the admission (a `PolicyViolation` referencing `require-signed-images-default`),

   * calls the `i1log` CLI again to append a **DENY** event for step `C7_UNSIGNED_PATH` into the **same** evidence file.

6. **Summary + local evidence location**

   At the end, the script prints:

   * a final summary stating that:

     * the signed image was admitted and is running, and
     * the unsigned image was blocked and did **not** replace the signed one;
   * the path to the evidence file and the correlation ID used.

   Example tail output (shape only, timestamps will differ):

   ```text
   [I1] Evidence written to: evidence/logs/i1/demo_i1_20251116T074533Z.jsonl
   [I1] Correlation ID: demo_i1_20251116T074533Z_61884
   ```

   One run of `demo_i1.sh` → **one evidence file** that contains the ALLOW + DENY story for I₁.

7. **S₁B: WORM upload to S3**

   At the end of the script, an additional step runs:

   * `scripts/ship_i1_evidence.sh "${I1_EVIDENCE_PATH}"`

   This uploads the local evidence file to an S3 bucket with Object Lock enabled:

   * Bucket: `prufwerk-i1-evidence-worm`
   * Key prefix: `i1/`
   * Key shape: `i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl`

   Example (shape only):

   ```text
   [S1B] Evidence successfully pinned to WORM (S3 bucket: prufwerk-i1-evidence-worm)
   ```

---

## 3. How to verify the I₁ evidence (local file)

### 3.1 Run the verifier over a specific evidence file

Pick the evidence file printed by `demo_i1.sh` (pattern: `evidence/logs/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl`) and run:

```bash
go run ./cmd/i1chaincheck \
  -file evidence/logs/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl
```

The verifier checks:

* that there is **at least one** `ALLOW` event for `docker.io/seejovin93/prufwerk:latest`,
* that there are **no** `ALLOW` events for `docker.io/seejovin93/prufwerk:unsigned-*`,
* that there is **at least one** `DENY` event for `docker.io/seejovin93/prufwerk:unsigned-*`,
* that the **hash chain** over all events in the file is valid.

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

This confirms that the **evidence file itself** matches the I₁ invariant:

* signed image → admitted (`ALLOW`),
* unsigned image → blocked (`DENY`),
* all events are consistent under a hash chain (no tampering detected).

---

## 4. S₁B — WORM pinning on S3 (Object Lock)

Slice S₁B takes the local JSONL evidence file and pins it into a **WORM-capable S3 bucket** so that a normal evidence writer cannot delete historical evidence.

### 4.1 Where the evidence goes

When `./scripts/demo_i1.sh` finishes successfully, it uploads the evidence file to:

* Bucket: `prufwerk-i1-evidence-worm`
* Region: `ap-east-2`
* Prefix: `i1/`
* Key shape: `i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl`

For example, a run might produce:

```text
s3://prufwerk-i1-evidence-worm/i1/demo_i1_20251116T162340Z.jsonl
```

A dedicated AWS CLI profile (example): `prufwerk-evidence-writer` is used by the shipping script.

### 4.2 Verifying an evidence file fetched from S3

An auditor (or you) can verify the evidence **directly from S3**:

1. Download the JSONL file from S3:

   ```bash
   aws s3 cp \
     s3://prufwerk-i1-evidence-worm/i1/demo_i1_YYYYMMDDTHHMMSSZ.jsonl \
     /tmp/evidence_from_s3.jsonl \
     --profile prufwerk-evidence-writer
   ```

2. Run the verifier:

   ```bash
   go run ./cmd/i1chaincheck \
     -file /tmp/evidence_from_s3.jsonl
   ```

   On success, you should see:

   ```text
   [I1 hash-chain] OK: 2 event(s) verified
   ```

   plus the same semantic checks as for the local file (ALLOW for signed, DENY for unsigned, no ALLOW for unsigned).

This shows that **given only the repo and an evidence file retrieved from the WORM bucket**, an independent party can re-check I₁.

### 4.3 WORM behaviour: delete vs new objects

The WORM story for S₁B is:

* The evidence writer (AWS profile `prufwerk-evidence-writer`) **cannot delete** evidence objects under `i1/`:

  ```bash
  aws s3 rm \
    s3://prufwerk-i1-evidence-worm/i1/demo_i1_20251116T162340Z.jsonl \
    --profile prufwerk-evidence-writer
  ```

  Result (shape):

  ```text
  An error occurred (AccessDenied) when calling the DeleteObject operation:
  User ... is not authorized to perform: s3:DeleteObject ...
  with an explicit deny in an identity-based policy
  ```

* The same writer **can create new objects** (including at new keys) under `i1/`:

  ```bash
  echo "TAMPER" > /tmp/tamper.jsonl

  aws s3 cp /tmp/tamper.jsonl \
    s3://prufwerk-i1-evidence-worm/i1/demo_i1_20251116T120000Z_abcd1234.jsonl \
    --profile prufwerk-evidence-writer
  ```

  This is expected and required: real I₁ runs must be able to create new evidence files at new keys.

If versioning + Object Lock are enabled on the bucket, then:

* A **delete** of an existing version is blocked for the writer.
* Any **overwrite** to an existing key creates a **new version**; older versions remain intact and retrievable (typically by an admin role).

For normal I₁ runs, each demo uses a **fresh key per run** (`demo_i1_YYYYMMDDTHHMMSSZ.jsonl`), so collisions and overwrites are not part of the happy path. The combination of:

* hash-chained JSONL per run,
* one key per run, and
* WORM + “no DeleteObject” for writers

gives a strong, auditable evidence story for I₁.
