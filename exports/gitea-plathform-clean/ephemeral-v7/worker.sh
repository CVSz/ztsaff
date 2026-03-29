#!/usr/bin/env bash
set -Eeuo pipefail

REDIS="redis"
GROUP="workers"
CONSUMER="c$(hostname)-$$"
STREAMS=("jobs:0" "jobs:1" "jobs:2" "jobs:3")

for S in "${STREAMS[@]}"; do
  redis-cli -h $REDIS XGROUP CREATE $S $GROUP 0 MKSTREAM 2>/dev/null || true
done

while true; do
  for S in "${STREAMS[@]}"; do
    MSG=$(redis-cli -h $REDIS XREADGROUP GROUP $GROUP $CONSUMER COUNT 1 BLOCK 1000 STREAMS $S '>')
    ID=$(echo "$MSG" | awk '/[0-9]-[0-9]/{print $1; exit}')
    JOB_ID=$(echo "$MSG" | awk '/job_id/{getline; print $1}')

    [[ -z "$JOB_ID" ]] && continue

    echo "[worker $(hostname)] job=$JOB_ID stream=$S"

    if /ephemeral/spawn-runner-wasm.sh "$JOB_ID"; then
      redis-cli -h $REDIS XACK $S $GROUP "$ID"
    else
      redis-cli -h $REDIS XADD jobs_dlq * job_id "$JOB_ID"
    fi
  done

  # failover: claim pending (visibility timeout)
  for S in "${STREAMS[@]}"; do
    redis-cli -h $REDIS XAUTOCLAIM $S $GROUP $CONSUMER 60000 0 COUNT 5 >/dev/null 2>&1 || true
  done
done
