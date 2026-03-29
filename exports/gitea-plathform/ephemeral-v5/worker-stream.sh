#!/usr/bin/env bash
set -Eeuo pipefail

REDIS="redis"
STREAM="jobs"
GROUP="workers"
CONSUMER="c$(hostname)-$$"
VISIBILITY=60
MAX_RETRY=5

redis-cli -h $REDIS XGROUP CREATE $STREAM $GROUP 0 MKSTREAM 2>/dev/null || true

while true; do
  MSG=$(redis-cli -h $REDIS XREADGROUP GROUP $GROUP $CONSUMER COUNT 1 BLOCK 0 STREAMS $STREAM '>')
  ID=$(echo "$MSG" | awk '/[0-9]-[0-9]/{print $1; exit}')
  JOB_ID=$(echo "$MSG" | awk '/job_id/{getline; print $1}')

  [[ -z "$ID" ]] && continue

  echo "[worker] job=$JOB_ID id=$ID"

  if /ephemeral/spawn-runner.sh "$JOB_ID"; then
    redis-cli -h $REDIS XACK $STREAM $GROUP $ID >/dev/null
  else
    RETRY=$(redis-cli -h $REDIS HINCRBY retry:$JOB_ID count 1)
    if (( RETRY > MAX_RETRY )); then
      redis-cli -h $REDIS XADD jobs_dlq * job_id "$JOB_ID"
      redis-cli -h $REDIS XACK $STREAM $GROUP $ID >/dev/null
    fi
  fi
done
