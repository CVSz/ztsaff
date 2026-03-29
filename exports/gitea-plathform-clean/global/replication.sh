#!/usr/bin/env bash
set -Eeuo pipefail

SRC="redis-a"
DST="redis-b"

while true; do
  MSG=$(redis-cli -h $SRC XREAD COUNT 10 STREAMS jobs:region-a 0)
  JOB_ID=$(echo "$MSG" | awk '/job_id/{getline; print $1}')

  [[ -n "$JOB_ID" ]] && \
    redis-cli -h $DST XADD jobs:region-b * job_id "$JOB_ID"

  sleep 2
done
