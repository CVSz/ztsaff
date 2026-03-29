#!/usr/bin/env bash
set -Eeuo pipefail

ETCD="http://etcd:2379"
REDIS="redis"

# leader election (simple lock)
if etcdctl --endpoints=$ETCD put /scheduler/leader "$(hostname)" --lease=10; then
  echo "[scheduler] leader=$(hostname)"
else
  echo "[scheduler] follower"
  sleep infinity
fi

while true; do
  # shard streams (global queue)
  for STREAM in jobs:0 jobs:1 jobs:2 jobs:3; do
    LEN=$(redis-cli -h $REDIS XLEN $STREAM || echo 0)

    # distribute to nodes
    NODES=$(etcdctl --endpoints=$ETCD get /nodes --prefix | wc -l)
    TARGET=$(( LEN / (NODES + 1) + 1 ))

    echo "[scheduler] $STREAM len=$LEN nodes=$NODES target=$TARGET"

    # update desired workers per node
    etcdctl --endpoints=$ETCD put /scale/$STREAM "$TARGET"
  done

  sleep 5
done
