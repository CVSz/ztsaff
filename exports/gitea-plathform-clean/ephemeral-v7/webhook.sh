#!/usr/bin/env bash
set -Eeuo pipefail

SECRET="$(cat /run/zgitea-installer/webhook_secret)"
PORT=8088

while true; do
  REQ=$(nc -l -p $PORT)
  BODY=$(echo "$REQ" | sed -n '/^\r$/,$p' | tail -n +2)
  SIG=$(echo "$REQ" | grep -i 'X-Hub-Signature-256:' | awk '{print $2}' | tr -d '\r')

  EXPECTED="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"
  [[ "$SIG" != "$EXPECTED" ]] && continue

  JOB_ID=$(echo "$BODY" | jq -r '.job.id')

  # shard by hash
  IDX=$(( JOB_ID % 4 ))
  STREAM="jobs:$IDX"

  redis-cli -h redis XADD "$STREAM" * job_id "$JOB_ID"
done
