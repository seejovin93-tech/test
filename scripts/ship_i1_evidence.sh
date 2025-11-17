#!/usr/bin/env bash
set -euo pipefail

PROFILE="prufwerk-evidence-writer"
BUCKET="prufwerk-i1-evidence-worm"
INVARIANT="I1"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <path-to-evidence-jsonl>"
  exit 1
fi

LOCAL_PATH="$1"

if [ ! -f "$LOCAL_PATH" ]; then
  echo "Error: file not found: $LOCAL_PATH"
  exit 1
fi

FILENAME="$(basename "$LOCAL_PATH")"
S3_KEY="i1/${FILENAME}"
S3_URI="s3://${BUCKET}/${S3_KEY}"

echo "Uploading evidence:"
echo "  Local: ${LOCAL_PATH}"
echo "  S3:    ${S3_URI}"

GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"

aws s3 cp "$LOCAL_PATH" "$S3_URI" \
  --profile "$PROFILE" \
  --only-show-errors

echo "Upload complete."
echo "Evidence pinned at: ${S3_URI}"
