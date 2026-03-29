#!/usr/bin/env bash
set -Eeuo pipefail

redis-cli -h redis XGROUP CREATE jobs workers 0 MKSTREAM 2>/dev/null || true

while true; do
  MSG=$(redis-cli -h redis XREADGROUP GROUP workers c1 COUNT 1 BLOCK 0 STREAMS jobs '>')
  ID=$(echo "$MSG" | awk '/[0-9]-[0-9]/{print $1; exit}')
  JOB_ID=$(echo "$MSG" | awk '/job_id/{getline; print $1}')

  [[ -z "$JOB_ID" ]] && continue

  if /ephemeral/spawn-runner-wasm.sh "$JOB_ID"; then
    redis-cli -h redis XACK jobs workers "$ID"
  else
    redis-cli -h redis XADD jobs_dlq * job_id "$JOB_ID"
  fi
done
