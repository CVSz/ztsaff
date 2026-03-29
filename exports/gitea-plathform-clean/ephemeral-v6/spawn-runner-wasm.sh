#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="$1"
WORKDIR="$(mktemp -d /tmp/wasm-${JOB_ID}-XXXX)"

echo "[wasm-runner] job=$JOB_ID"

# fetch wasm job payload (จาก queue metadata)
WASM_URL=$(redis-cli -h redis HGET job:$JOB_ID wasm_url)

curl -s "$WASM_URL" -o "$WORKDIR/job.wasm"

# execute (sandbox)
wasmtime run --dir="$WORKDIR" "$WORKDIR/job.wasm" || true

# pack artifact
tar czf /tmp/${JOB_ID}.tgz -C "$WORKDIR" .

# upload (reuse presigned)
PRESIGNED=$(redis-cli -h redis HGET job:$JOB_ID presigned)
curl -s -X PUT "$PRESIGNED" --data-binary @/tmp/${JOB_ID}.tgz

rm -rf "$WORKDIR"
echo "[wasm-runner] done"
