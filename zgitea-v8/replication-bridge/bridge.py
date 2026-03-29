import hashlib
import json
import os
import time
from typing import Dict, List

import redis

REGIONS = [r.strip() for r in os.getenv("REGIONS", "region-a,region-b,region-c").split(",") if r.strip()]
REDIS_HOSTS: Dict[str, str] = {
    region: os.getenv(f"{region.upper().replace('-', '_')}_REDIS", f"{region}-redis") for region in REGIONS
}
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
STREAM_SHARDS = int(os.getenv("STREAM_SHARDS", "4"))
BLOCK_MS = int(os.getenv("BLOCK_MS", "2000"))
CONSUMER_GROUP = os.getenv("BRIDGE_GROUP", "bridge")
CONSUMER_NAME = os.getenv("BRIDGE_CONSUMER", "bridge-1")

clients = {region: redis.Redis(host=host, port=REDIS_PORT, decode_responses=True) for region, host in REDIS_HOSTS.items()}


def stream_names(region: str) -> List[str]:
    return [f"jobs:{region}:{i}" for i in range(STREAM_SHARDS)]


def ensure_groups() -> None:
    for region in REGIONS:
        client = clients[region]
        for stream in stream_names(region):
            try:
                client.xgroup_create(stream, CONSUMER_GROUP, id="0", mkstream=True)
            except redis.ResponseError as exc:
                if "BUSYGROUP" not in str(exc):
                    raise


def replication_id(source_region: str, stream: str, message_id: str) -> str:
    h = hashlib.sha256(f"{source_region}:{stream}:{message_id}".encode()).hexdigest()
    return h


def fanout(source_region: str, stream: str, message_id: str, payload: Dict[str, str]) -> None:
    rid = replication_id(source_region, stream, message_id)
    body = dict(payload)
    body["replication_id"] = rid
    body["source_region"] = source_region
    body["source_stream"] = stream
    body["source_message_id"] = message_id

    for target in REGIONS:
        if target == source_region:
            continue
        target_client = clients[target]
        dedup_key = f"replicated:{rid}:{target}"
        if target_client.set(dedup_key, "1", nx=True, ex=7 * 24 * 3600):
            shard = int(hashlib.md5(rid.encode()).hexdigest(), 16) % STREAM_SHARDS
            target_stream = f"jobs:{target}:{shard}"
            target_client.xadd(target_stream, body, maxlen=20000, approximate=True)


def poll_region(region: str) -> None:
    client = clients[region]
    streams = stream_names(region)
    stream_offsets = {name: ">" for name in streams}
    response = client.xreadgroup(CONSUMER_GROUP, CONSUMER_NAME, stream_offsets, count=50, block=BLOCK_MS)

    for stream, messages in response:
        for message_id, payload in messages:
            if payload.get("source_region") == region:
                client.xack(stream, CONSUMER_GROUP, message_id)
                continue

            fanout(region, stream, message_id, payload)
            client.xack(stream, CONSUMER_GROUP, message_id)


def reclaim_stale(region: str) -> None:
    client = clients[region]
    for stream in stream_names(region):
        try:
            stale = client.xautoclaim(stream, CONSUMER_GROUP, CONSUMER_NAME, min_idle_time=60000, start_id="0-0", count=100)
        except redis.ResponseError:
            continue
        _, claimed, _ = stale
        for message_id, _ in claimed:
            client.xack(stream, CONSUMER_GROUP, message_id)


def main() -> None:
    ensure_groups()
    while True:
        for region in REGIONS:
            poll_region(region)
            reclaim_stale(region)
        time.sleep(0.1)


if __name__ == "__main__":
    main()
