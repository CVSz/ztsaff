import math
import os
import time
from collections import defaultdict

import redis

REGION = os.getenv("REGION", "region-a")
REDIS_HOST = os.getenv("REDIS_HOST", f"{REGION}-redis")
SHARDS = int(os.getenv("STREAM_SHARDS", "4"))
TARGET_QUEUE_PER_WORKER = int(os.getenv("TARGET_QUEUE_PER_WORKER", "20"))
MIN_WORKERS = int(os.getenv("MIN_WORKERS", "2"))
MAX_WORKERS = int(os.getenv("MAX_WORKERS", "200"))
COOLDOWN_SEC = int(os.getenv("COOLDOWN_SEC", "20"))

r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
last_scale = defaultdict(lambda: 0.0)


def queue_depth() -> int:
    total = 0
    for shard in range(SHARDS):
        stream = f"dispatch:{REGION}:{shard}"
        info = r.xinfo_stream(stream)
        total += info.get("length", 0)
    return total


def desired_workers(depth: int) -> int:
    return max(MIN_WORKERS, min(MAX_WORKERS, math.ceil(depth / max(1, TARGET_QUEUE_PER_WORKER))))


def scale_to(count: int) -> None:
    now = time.time()
    if now - last_scale[REGION] < COOLDOWN_SEC:
        return
    # Deterministic file-based control plane output.
    with open(f"/tmp/scale-{REGION}.json", "w", encoding="utf-8") as f:
        f.write(f'{{"region":"{REGION}","desired_workers":{count},"ts":{int(now)}}}')
    last_scale[REGION] = now


def run() -> None:
    while True:
        depth = queue_depth()
        desired = desired_workers(depth)
        scale_to(desired)
        time.sleep(5)


if __name__ == "__main__":
    run()
