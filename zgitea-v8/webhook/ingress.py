import hashlib
import hmac
import json
import os
from pathlib import Path

import redis
from fastapi import FastAPI, Header, HTTPException, Request

REGION = os.getenv("REGION", "region-a")
REDIS_HOST = os.getenv("REDIS_HOST", f"{REGION}-redis")
SHARDS = int(os.getenv("STREAM_SHARDS", "4"))
SECRETS_DIR = Path(os.getenv("SECRETS_DIR", "/run/secrets"))

r = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
app = FastAPI(title="ZGitea Webhook Ingress")


def read_secret(name: str) -> bytes:
    p = SECRETS_DIR / name
    if not p.exists():
        raise RuntimeError(f"missing secret file: {p}")
    return p.read_bytes().strip()


def verify(signature: str, payload: bytes) -> None:
    key = read_secret("webhook_hmac_key")
    digest = hmac.new(key, payload, hashlib.sha256).hexdigest()
    expected = f"sha256={digest}"
    if not hmac.compare_digest(signature or "", expected):
        raise HTTPException(status_code=401, detail="Invalid webhook signature")


@app.head("/health")
@app.get("/health")
def health():
    return {"status": "ok", "region": REGION}


@app.post("/webhook")
async def webhook(request: Request, x_hub_signature_256: str = Header(default="")):
    raw = await request.body()
    verify(x_hub_signature_256, raw)
    payload = json.loads(raw)

    job_id = payload["job_id"]
    shard = int(hashlib.sha256(job_id.encode()).hexdigest(), 16) % SHARDS
    stream = f"jobs:{REGION}:{shard}"

    message = {
        "job_id": job_id,
        "repo": payload.get("repo", ""),
        "commit": payload.get("commit", ""),
        "wasm_base64": payload["wasm_base64"],
        "input_base64": payload.get("input_base64", ""),
    }

    r.xadd(stream, message, maxlen=20000, approximate=True)
    return {"accepted": True, "stream": stream}
