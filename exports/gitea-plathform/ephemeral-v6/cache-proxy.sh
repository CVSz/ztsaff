#!/usr/bin/env bash
set -Eeuo pipefail

S3="$(cat /run/zgitea-installer/s3_endpoint)"
BUCKET="$(cat /run/zgitea-installer/s3_bucket)"

KEY="$1"
FILE="$2"

HASH=$(sha256sum "$FILE" | awk '{print $1}')

# check cache
if curl -sf "$S3/$BUCKET/cache/$HASH" >/dev/null; then
  echo "[cache] hit $HASH"
  exit 0
fi

# upload
curl -s -X PUT "$S3/$BUCKET/cache/$HASH" \
  --data-binary @"$FILE"

echo "[cache] stored $HASH"
