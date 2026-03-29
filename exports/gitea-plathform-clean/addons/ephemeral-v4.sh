#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
EPH_DIR="${BASE_DIR}/ephemeral-v4"

mkdir -p "$EPH_DIR"

############################################
# 0) PREP SECRETS (file-based only)
############################################
# required:
# - ${SECRETS_DIR}/runner_token
# - ${SECRETS_DIR}/webhook_secret  (HMAC)
# - ${SECRETS_DIR}/s3_access_key
# - ${SECRETS_DIR}/s3_secret_key
# - ${SECRETS_DIR}/s3_bucket
# - ${SECRETS_DIR}/s3_endpoint (e.g. http://minio:9000)

for f in runner_token webhook_secret s3_access_key s3_secret_key s3_bucket s3_endpoint; do
  if [[ ! -s "${SECRETS_DIR}/${f}" ]]; then
    echo "[WARN] missing ${f} → generating placeholder (override later)"
    echo "change-me-${f}" > "${SECRETS_DIR}/${f}"
    chmod 600 "${SECRETS_DIR}/${f}"
  fi
done

############################################
# 1) SPAWN RUNNER (per job, sandbox)
############################################
cat > "${EPH_DIR}/spawn-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="$1"
NAME="runner-${JOB_ID}"
WORKDIR="$(mktemp -d /tmp/runner-${JOB_ID}-XXXX)"

RUNTIME_FILE="/run/zgitea-installer/runtime"
RUNTIME="$(cat "$RUNTIME_FILE" 2>/dev/null || echo runc)"

# S3 config (MinIO compatible)
S3_ENDPOINT="$(cat /run/zgitea-installer/s3_endpoint)"
S3_BUCKET="$(cat /run/zgitea-installer/s3_bucket)"
AWS_ACCESS_KEY_ID="$(cat /run/zgitea-installer/s3_access_key)"
AWS_SECRET_ACCESS_KEY="$(cat /run/zgitea-installer/s3_secret_key)"

echo "[spawn] job=$JOB_ID runtime=$RUNTIME"

docker run --rm -d \
  --name "$NAME" \
  --runtime="$RUNTIME" \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /workspace \
  -v /run/zgitea-installer:/run/secrets:ro \
  -v "$WORKDIR":/workspace \
  --network none \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e S3_ENDPOINT \
  -e S3_BUCKET \
  gitea/act_runner:latest \
  sh -c '
    set -e
    TOKEN=$(cat /run/secrets/runner_token)

    act_runner register \
      --instance http://gitea:3000 \
      --token "$TOKEN" \
      --name '"$NAME"' \
      --labels ephemeral || true

    # run once
    act_runner daemon --once

    # artifact upload (best-effort)
    if [ -d /workspace ]; then
      apk add --no-cache curl >/dev/null 2>&1 || true
      tar czf /tmp/artifact.tgz -C /workspace . || true
      if [ -s /tmp/artifact.tgz ]; then
        # simple PUT (MinIO presigned or open bucket)
        curl -s -X PUT "${S3_ENDPOINT}/${S3_BUCKET}/'"$NAME"'.tgz" \
          -H "Content-Type: application/gzip" \
          --data-binary @/tmp/artifact.tgz || true
      fi
    fi
  '

# wait container exit (max 1h)
timeout 3600 bash -c "until ! docker ps --format '{{.Names}}' | grep -q '^${NAME}$'; do sleep 3; done" || true

# cleanup
rm -rf "$WORKDIR"
echo "[spawn] done job=$JOB_ID"
EOF
chmod +x "${EPH_DIR}/spawn-runner.sh"

############################################
# 2) WORKER (Redis BRPOP → spawn)
############################################
cat > "${EPH_DIR}/worker.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

REDIS_HOST="redis"
QUEUE="jobs"

echo "[worker] start"

while true; do
  # block pop
  JOB=$(redis-cli -h "$REDIS_HOST" BRPOP "$QUEUE" 0 | awk '{print $2}')
  if [[ -n "$JOB" ]]; then
    echo "[worker] job=$JOB"
    /ephemeral/spawn-runner.sh "$JOB" || true
  fi
done
EOF
chmod +x "${EPH_DIR}/worker.sh"

############################################
# 3) AUTOSCALER (scale workers by queue len)
############################################
cat > "${EPH_DIR}/autoscaler.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

REDIS_HOST="redis"
QUEUE="jobs"
SERVICE="worker"
MAX=10
MIN=1

while true; do
  LEN=$(redis-cli -h "$REDIS_HOST" LLEN "$QUEUE" || echo 0)

  # desired workers = clamp(LEN/2 + 1, MIN..MAX)
  DESIRED=$(( LEN / 2 + 1 ))
  (( DESIRED < MIN )) && DESIRED=$MIN
  (( DESIRED > MAX )) && DESIRED=$MAX

  CURRENT=$(docker ps --filter "name=${SERVICE}_" --format '{{.Names}}' | wc -l || echo 0)

  echo "[autoscaler] len=$LEN desired=$DESIRED current=$CURRENT"

  if (( CURRENT < DESIRED )); then
    ADD=$(( DESIRED - CURRENT ))
    for i in $(seq 1 $ADD); do
      docker compose -f docker-compose.ephemeral-v4.yml up -d --scale worker=$((CURRENT + i)) worker >/dev/null 2>&1 || true
    done
  elif (( CURRENT > DESIRED )); then
    # scale down by removing extra containers
    REMOVE=$(( CURRENT - DESIRED ))
    docker ps --filter "name=${SERVICE}_" --format '{{.Names}}' | tail -n "$REMOVE" | xargs -r docker rm -f
  fi

  sleep 5
done
EOF
chmod +x "${EPH_DIR}/autoscaler.sh"

############################################
# 4) WEBHOOK (HMAC verify → enqueue)
############################################
cat > "${EPH_DIR}/webhook.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

PORT=8088
SECRET="$(cat /run/zgitea-installer/webhook_secret)"
REDIS_HOST="redis"
QUEUE="jobs"

echo "[webhook] listen :$PORT"

# simple HTTP parser via nc (POST only)
while true; do
  REQUEST=$(nc -l -p $PORT)
  BODY=$(echo "$REQUEST" | sed -n '/^\r$/,$p' | tail -n +2)
  SIG=$(echo "$REQUEST" | grep -i 'X-Hub-Signature-256:' | awk '{print $2}' | tr -d '\r')

  # compute HMAC
  EXPECTED="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"

  if [[ "$SIG" != "$EXPECTED" ]]; then
    echo "[webhook] invalid signature"
    continue
  fi

  JOB_ID=$(echo "$BODY" | jq -r '.job.id // empty')
  if [[ -n "$JOB_ID" ]]; then
    redis-cli -h "$REDIS_HOST" LPUSH "$QUEUE" "$JOB_ID" >/dev/null
    echo "[webhook] enqueued job=$JOB_ID"
  fi
done
EOF
chmod +x "${EPH_DIR}/webhook.sh"

############################################
# 5) COMPOSE (Redis + worker + autoscaler + webhook)
############################################
cat > "${BASE_DIR}/docker-compose.ephemeral-v4.yml" <<EOF
services:
  redis:
    image: redis:7-alpine
    command: ["redis-server","--save","","--appendonly","no"]
    ports: ["127.0.0.1:6379:6379"]

  worker:
    image: alpine:3
    volumes:
      - ${EPH_DIR}:/ephemeral
      - ${SECRETS_DIR}:/run/zgitea-installer:ro
      - /var/run/docker.sock:/var/run/docker.sock
    entrypoint: ["/bin/sh","-c"]
    command: "apk add --no-cache bash curl jq redis && /ephemeral/worker.sh"
    deploy:
      replicas: 1

  autoscaler:
    image: alpine:3
    volumes:
      - ${EPH_DIR}:/ephemeral
      - /var/run/docker.sock:/var/run/docker.sock
    entrypoint: ["/bin/sh","-c"]
    command: "apk add --no-cache bash redis docker-cli && /ephemeral/autoscaler.sh"

  webhook:
    image: alpine:3
    ports: ["127.0.0.1:8088:8088"]
    volumes:
      - ${EPH_DIR}:/ephemeral
      - ${SECRETS_DIR}:/run/zgitea-installer:ro
    entrypoint: ["/bin/sh","-c"]
    command: "apk add --no-cache bash netcat-openbsd jq openssl redis && /ephemeral/webhook.sh"
EOF

############################################
# 6) START
############################################
docker compose -f "${BASE_DIR}/docker-compose.ephemeral-v4.yml" up -d

echo "[EPHEMERAL v4] redis + worker + autoscaler + webhook started"
