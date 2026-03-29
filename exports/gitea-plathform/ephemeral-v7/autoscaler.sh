#!/usr/bin/env bash
set -Eeuo pipefail

ETCD="http://etcd:2379"

while true; do
  for S in jobs:0 jobs:1 jobs:2 jobs:3; do
    TARGET=$(etcdctl --endpoints=$ETCD get /scale/$S | tail -n1)

    CURRENT=$(docker ps --filter "name=worker_" | wc -l || echo 0)

    if (( CURRENT < TARGET )); then
      docker compose -f docker-compose.ephemeral-v7.yml up -d --scale worker=$TARGET worker >/dev/null 2>&1
    fi
  done

  sleep 5
done
