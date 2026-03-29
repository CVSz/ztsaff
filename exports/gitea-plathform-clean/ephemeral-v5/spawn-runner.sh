#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="$1"
NAME="runner-${JOB_ID}"
WORKDIR="$(mktemp -d /tmp/runner-${JOB_ID}-XXXX)"

RUNTIME="$(cat /run/zgitea-installer/runtime 2>/dev/null || echo runc)"
PRESIGN_API="$(cat /run/zgitea-installer/presign_api)"   # e.g. http://minio-proxy:9001/presign
CALLBACK_API="$(cat /run/zgitea-installer/callback_api)" # e.g. http://gitea:3000/api/...

# --- per-job network (bridge) ---
NET="jobnet-${JOB_ID}"
docker network create --driver bridge --internal "$NET" >/dev/null 2>&1 || true

# --- seccomp profile ---
SECCOMP="/ephemeral/seccomp-runner.json"

# --- get presigned URL ---
PRESIGNED_URL="$(curl -s -X POST "$PRESIGN_API" \
  -H "Content-Type: application/json" \
  -d "{\"job_id\":\"${JOB_ID}\",\"name\":\"${NAME}.tgz.enc\"}" \
  | jq -r '.url')"

echo "[spawn] job=$JOB_ID"

CID=$(docker run -d \
  --name "$NAME" \
  --runtime="$RUNTIME" \
  --read-only \
  --security-opt "no-new-privileges:true" \
  --security-opt "seccomp=${SECCOMP}" \
  --tmpfs /tmp \
  --tmpfs /workspace \
  -v /run/zgitea-installer:/run/secrets:ro \
  -v "$WORKDIR":/workspace \
  --network "$NET" \
  gitea/act_runner:latest \
  sh -c '
    set -e
    TOKEN=$(cat /run/secrets/runner_token)

    act_runner register \
      --instance http://gitea:3000 \
      --token "$TOKEN" \
      --name '"$NAME"' \
      --labels ephemeral || true

    act_runner daemon --once
  ')

# --- wait finish (visibility window) ---
timeout 3600 bash -c "until ! docker ps --format '{{.Names}}' | grep -q '^${NAME}$'; do sleep 3; done" || true

# --- encrypt + upload artifact ---
if [ -d "$WORKDIR" ]; then
  tar czf /tmp/artifact.tgz -C "$WORKDIR" . || true

  if [ -s /tmp/artifact.tgz ]; then
    KEY="$(openssl rand -hex 32)"
    openssl enc -aes-256-cbc -salt -in /tmp/artifact.tgz -out /tmp/artifact.enc -k "$KEY"

    curl -s -X PUT "$PRESIGNED_URL" \
      -H "Content-Type: application/octet-stream" \
      --data-binary @/tmp/artifact.enc || true

    # callback success
    curl -s -X POST "$CALLBACK_API" \
      -H "Content-Type: application/json" \
      -d "{\"job_id\":\"${JOB_ID}\",\"status\":\"success\",\"key\":\"${KEY}\"}" >/dev/null
  fi
fi

# cleanup
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker network rm "$NET" >/dev/null 2>&1 || true
rm -rf "$WORKDIR"

echo "[spawn] done job=$JOB_ID"
