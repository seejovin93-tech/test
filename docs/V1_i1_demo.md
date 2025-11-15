# Prufwerk V1 — I₁ demo

## What I₁ is

- Invariant: **“no valid signature / no provenance → no run”** for `docker.io/seejovin93/prufwerk*` in namespace `default`.
- This demo proves that:
  - Signed image `:latest` is admitted and runs.
  - Unsigned `:unsigned-<timestamp>` is blocked at admission.

## What this script does (`scripts/demo_i1.sh`)

1. Ensures kind cluster + Kyverno installed.
2. Deploys **signed** `:latest` and runs `smoke.sh`.
3. Builds and pushes a **new, unsigned** image `:unsigned-<timestamp>`.
4. Attempts to roll out the unsigned image → Kyverno **DENY**.
5. Shows that Deployment still points to the signed image.

## How to run

```bash
git clone https://github.com/<you>/<prufwerk>.git
cd prufwerk
./scripts/demo_i1.sh
