import hashlib
import json
import os
import time
from contextlib import contextmanager
from typing import Optional

import etcd3
import redis

REGION = os.getenv("REGION", "region-a")
SHARDS = int(os.getenv("STREAM_SHARDS", "4"))
REDIS_HOST = os.getenv("REDIS_HOST", f"{REGION}-redis")
ETCD_HOST = os.getenv("ETCD_HOST", f"{REGION}-etcd")
LEASE_TTL = int(os.getenv("LEASE_TTL", "10"))
CONSUMER_GROUP = os.getenv("SCHEDULER_GROUP", "scheduler")
CONSUMER = os.getenv("SCHEDULER_CONSUMER", f"{REGION}-scheduler-1")

r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
etcd = etcd3.client(host=ETCD_HOST, port=2379)


def stream_for(job_id: str) -> str:
    shard = int(hashlib.sha256(job_id.encode()).hexdigest(), 16) % SHARDS
    return f"jobs:{REGION}:{shard}"


@contextmanager
def region_leader_lock():
    lock = etcd.lock(f"/zgitea/leader/{REGION}", ttl=LEASE_TTL)
    acquired = lock.acquire(timeout=2)
    if not acquired:
        yield False
        return
    try:
        yield True
    finally:
        lock.release()


def ensure_groups() -> None:
    for shard in range(SHARDS):
        stream = f"jobs:{REGION}:{shard}"
        try:
            r.xgroup_create(stream, CONSUMER_GROUP, id="0", mkstream=True)
        except redis.ResponseError as exc:
            if "BUSYGROUP" not in str(exc):
                raise


def dispatch(message_id: str, payload: dict) -> None:
    job_id = payload.get("job_id", message_id)
    worker_stream = f"dispatch:{REGION}:{int(hashlib.md5(job_id.encode()).hexdigest(), 16) % SHARDS}"
    payload["dispatched_at"] = str(int(time.time()))
    r.xadd(worker_stream, payload, maxlen=10000, approximate=True)


def reconcile_stale(stream: str) -> None:
    next_id, claimed, _ = r.xautoclaim(stream, CONSUMER_GROUP, CONSUMER, min_idle_time=60000, start_id="0-0", count=25)
    _ = next_id
    for message_id, payload in claimed:
        dispatch(message_id, payload)
        r.xack(stream, CONSUMER_GROUP, message_id)


def run_once() -> None:
    for shard in range(SHARDS):
        stream = f"jobs:{REGION}:{shard}"
        messages = r.xreadgroup(CONSUMER_GROUP, CONSUMER, {stream: ">"}, count=50, block=1200)
        for _, batch in messages:
            for message_id, payload in batch:
                dispatch(message_id, payload)
                r.xack(stream, CONSUMER_GROUP, message_id)
        reconcile_stale(stream)


def main() -> None:
    ensure_groups()
    while True:
        with region_leader_lock() as is_leader:
            if is_leader:
                run_once()
            else:
                time.sleep(1)


if __name__ == "__main__":
    main()
