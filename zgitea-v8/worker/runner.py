import base64
import hashlib
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

import redis
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

REGION = os.getenv("REGION", "region-a")
REDIS_HOST = os.getenv("REDIS_HOST", f"{REGION}-redis")
MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", f"http://{REGION}-minio:9000")
SHARDS = int(os.getenv("STREAM_SHARDS", "4"))
CONSUMER_GROUP = os.getenv("WORKER_GROUP", "workers")
CONSUMER = os.getenv("WORKER_CONSUMER", f"{REGION}-worker-1")
SECRETS_DIR = Path(os.getenv("SECRETS_DIR", "/run/secrets"))

r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)


def read_secret(name: str) -> bytes:
    path = SECRETS_DIR / name
    if not path.exists():
        raise FileNotFoundError(f"Missing secret file: {path}")
    return path.read_bytes().strip()


def ensure_groups() -> None:
    for shard in range(SHARDS):
        stream = f"dispatch:{REGION}:{shard}"
        try:
            r.xgroup_create(stream, CONSUMER_GROUP, id="0", mkstream=True)
        except redis.ResponseError as exc:
            if "BUSYGROUP" not in str(exc):
                raise


def run_wasm(module_path: Path, stdin_payload: bytes) -> bytes:
    cmd = ["wasmtime", "run", str(module_path), "--invoke", "main"]
    proc = subprocess.run(cmd, input=stdin_payload, capture_output=True, check=False, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", errors="ignore"))
    return proc.stdout


def encrypt_blob(data: bytes, key: bytes) -> dict:
    nonce = os.urandom(12)
    aesgcm = AESGCM(key)
    ciphertext = aesgcm.encrypt(nonce, data, associated_data=None)
    return {
        "nonce": base64.b64encode(nonce).decode(),
        "ciphertext": base64.b64encode(ciphertext).decode(),
        "sha256": hashlib.sha256(data).hexdigest(),
        "algo": "AES-256-GCM",
    }


def process_job(job: dict) -> dict:
    wasm_bytes = base64.b64decode(job["wasm_base64"])
    input_payload = base64.b64decode(job.get("input_base64", ""))

    with tempfile.TemporaryDirectory(dir="/tmp") as td:
        module_path = Path(td) / "job.wasm"
        module_path.write_bytes(wasm_bytes)
        output = run_wasm(module_path, input_payload)

    key = read_secret("artifact_key")
    if len(key) != 32:
        raise ValueError("artifact_key must be 32 bytes for AES-256")
    encrypted = encrypt_blob(output, key)

    return {
        "job_id": job["job_id"],
        "finished_at": str(int(time.time())),
        "artifact": json.dumps(encrypted),
        "artifact_endpoint": MINIO_ENDPOINT,
    }


def ack_result(stream: str, message_id: str, payload: dict) -> None:
    result_stream = f"results:{REGION}"
    r.xadd(result_stream, payload, maxlen=100000, approximate=True)
    r.xack(stream, CONSUMER_GROUP, message_id)


def run() -> None:
    ensure_groups()
    while True:
        for shard in range(SHARDS):
            stream = f"dispatch:{REGION}:{shard}"
            entries = r.xreadgroup(CONSUMER_GROUP, CONSUMER, {stream: ">"}, count=4, block=1000)
            for _, batch in entries:
                for message_id, payload in batch:
                    try:
                        result = process_job(payload)
                        ack_result(stream, message_id, result)
                    except Exception as exc:
                        r.xadd(
                            f"dlq:{REGION}",
                            {
                                "message_id": message_id,
                                "stream": stream,
                                "error": str(exc),
                                "payload": json.dumps(payload),
                            },
                            maxlen=10000,
                            approximate=True,
                        )
                        r.xack(stream, CONSUMER_GROUP, message_id)


if __name__ == "__main__":
    run()
