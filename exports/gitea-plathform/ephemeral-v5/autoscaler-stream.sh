#!/usr/bin/env bash
set -Eeuo pipefail

REDIS="redis"
STREAM="jobs"

while true; do
  LEN=$(redis-cli -h $REDIS XLEN $STREAM)
  TARGET=$(( LEN / 2 + 1 ))
  (( TARGET < 1 )) && TARGET=1
  (( TARGET > 10 )) && TARGET=10

  docker compose -f docker-compose.ephemeral-v5.yml up -d --scale worker=$TARGET worker >/dev/null 2>&1 || true
  sleep 5
done
