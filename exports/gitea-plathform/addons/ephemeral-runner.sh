
############################################
# EPHEMERAL RUNNER (v2 + v3)
############################################

mkdir -p "${BASE_DIR}/ephemeral"

############################################
# 1) QUEUE WORKER (pull jobs)
############################################
cat > "${BASE_DIR}/ephemeral/queue-worker.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

GITEA_URL="http://gitea:3000"
TOKEN_FILE="/run/zgitea-installer/runner_token"
RUNTIME="${RUNTIME:-runc}"

while true; do
  # simulate queue poll (Gitea API /jobs pending)
  JOB_ID=$(curl -s "$GITEA_URL/api/actions/runners/jobs" \
    -H "Authorization: token $(cat $TOKEN_FILE)" \
    | jq -r '.jobs[0].id // empty')

  if [[ -n "$JOB_ID" ]]; then
    echo "[queue] job=$JOB_ID"

    bash /ephemeral/spawn-runner.sh "$JOB_ID"
  fi

  sleep 3
done
EOF
chmod +x "${BASE_DIR}/ephemeral/queue-worker.sh"

############################################
# 2) SPAWN RUNNER (per job)
############################################
cat > "${BASE_DIR}/ephemeral/spawn-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

JOB_ID="$1"
NAME="runner-$JOB_ID"
WORKDIR="/tmp/runner-$JOB_ID"

mkdir -p "$WORKDIR"

docker run -d --rm \
  --name "$NAME" \
  --runtime=${RUNTIME} \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /workspace \
  -v /run/zgitea-installer:/run/secrets:ro \
  -v "$WORKDIR":/workspace \
  --network none \
  gitea/act_runner:latest \
  sh -c "
    TOKEN=\$(cat /run/secrets/runner_token);
    act_runner register \
      --instance http://gitea:3000 \
      --token \$TOKEN \
      --name $NAME \
      --labels ephemeral;

    act_runner daemon --once;

    echo '[runner] done → cleanup';
  "

# cleanup workspace
rm -rf "$WORKDIR"
EOF
chmod +x "${BASE_DIR}/ephemeral/spawn-runner.sh"

############################################
# 3) WEBHOOK LISTENER (v3)
############################################
cat > "${BASE_DIR}/ephemeral/webhook-server.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

PORT=8088

echo "[webhook] listening :$PORT"

while true; do
  # simple netcat listener (lightweight)
  REQUEST=$(nc -l -p $PORT)

  JOB_ID=$(echo "$REQUEST" | grep -o '"job_id":[0-9]*' | cut -d: -f2)

  if [[ -n "$JOB_ID" ]]; then
    echo "[webhook] job=$JOB_ID"
    bash /ephemeral/spawn-runner.sh "$JOB_ID"
  fi
done
EOF
chmod +x "${BASE_DIR}/ephemeral/webhook-server.sh"

############################################
# 4) DOCKER SERVICE (ephemeral system)
############################################
cat > "${BASE_DIR}/docker-compose.ephemeral.yml" <<EOF
services:
  queue:
    image: alpine:3
    volumes:
      - ${BASE_DIR}/ephemeral:/ephemeral
      - /run/zgitea-installer:/run/zgitea-installer:ro
    entrypoint: ["/bin/sh","-c"]
    command: "apk add --no-cache curl jq && /ephemeral/queue-worker.sh"
    networks: [default]

  webhook:
    image: alpine:3
    ports: ["127.0.0.1:8088:8088"]
    volumes:
      - ${BASE_DIR}/ephemeral:/ephemeral
    entrypoint: ["/bin/sh","-c"]
    command: "apk add --no-cache netcat-openbsd && /ephemeral/webhook-server.sh"

EOF

############################################
# 5) START EPHEMERAL SYSTEM
############################################
docker compose -f docker-compose.ephemeral.yml up -d

echo "[EPHEMERAL] queue + webhook active"
