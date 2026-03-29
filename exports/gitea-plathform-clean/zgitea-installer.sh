#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
MON_DIR="${BASE_DIR}/monitoring"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# INSTALL BASE
############################################
apt-get update
apt-get install -y curl jq bc cron ca-certificates util-linux

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

############################################
# gVisor AUTO-DETECT (non-blocking)
############################################
RUNTIME="runc"
(
  install_gvisor() {
    curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/runsc \
      -o /usr/local/bin/runsc || return 1
    curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/containerd-shim-runsc-v1 \
      -o /usr/local/bin/containerd-shim-runsc-v1 || return 1
    chmod +x /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1
    systemctl restart docker
  }
  test_gvisor() {
    docker run --rm --runtime=runsc alpine echo OK >/dev/null 2>&1
  }
  install_gvisor || true
  if test_gvisor; then echo "runsc" > /tmp/runtime.sel; else echo "runc" > /tmp/runtime.sel; fi
) &

############################################
# TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=8M tmpfs "$SECRETS_DIR"

gen_secret() {
  [[ -f "$1" ]] || openssl rand -hex 32 > "$1"
  chmod 600 "$1"
}
gen_secret "$SECRETS_DIR/db_pass"
gen_secret "$SECRETS_DIR/app_secret"

############################################
# PROMETHEUS CONFIG (dir mount safe)
############################################
mkdir -p "$MON_DIR"
cat > "$MON_DIR/prometheus.yml" <<'EOF'
global:
  scrape_interval: 5s
scrape_configs:
  - job_name: node
    static_configs: [{targets: ['node-exporter:9100']}]
  - job_name: cadvisor
    static_configs: [{targets: ['cadvisor:8080']}]
EOF

############################################
# WAIT runtime detect (bounded)
############################################
for i in $(seq 1 10); do
  [[ -f /tmp/runtime.sel ]] && break
  sleep 1
done
RUNTIME=$(cat /tmp/runtime.sel 2>/dev/null || echo "runc")
echo "[INFO] runtime=$RUNTIME"

############################################
# COMPOSE (HEALTH-AWARE)
############################################
cd "$BASE_DIR"

cat > docker-compose.yml <<EOF
services:

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 3s
      retries: 20

  gitea:
    image: gitea/gitea:1.21-rootless
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/api/healthz"]
      interval: 3s
      retries: 20
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

  act_runner:
    image: gitea/act_runner:latest
    runtime: ${RUNTIME}
    read_only: true
    mem_limit: 512m
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    tmpfs: [/tmp]
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
    entrypoint: ["/bin/sh","-c"]
    command: >
      "
      echo '[runner] waiting token...';
      until [ -s /run/secrets/runner_token ]; do sleep 2; done;

      TOKEN=\$(cat /run/secrets/runner_token);

      if [ ! -f /data/.runner ]; then
        echo '[runner] registering...';
        act_runner register \
          --instance http://gitea:3000 \
          --token \$TOKEN \
          --name zgitea \
          --labels secure || true;
      fi;

      exec act_runner daemon;
      "

  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring:/etc/prometheus
    ports: ["127.0.0.1:9090:9090"]

  grafana:
    image: grafana/grafana
    ports: ["127.0.0.1:3001:3000"]

  node-exporter:
    image: prom/node-exporter
    network_mode: host

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ports: ["127.0.0.1:8080:8080"]

volumes:
  postgres_data:
EOF

############################################
# PARALLEL START (faster boot)
############################################
docker compose up -d postgres prometheus grafana node-exporter cadvisor

############################################
# WAIT POSTGRES HEALTH
############################################
echo "[INFO] waiting postgres..."
until docker inspect --format='{{.State.Health.Status}}' \
  $(docker ps --filter name=postgres -q) 2>/dev/null | grep -q healthy; do
  sleep 2
done

############################################
# START GITEA
############################################
docker compose up -d gitea

############################################
# WAIT GITEA HEALTH (bounded)
############################################
echo "[INFO] waiting gitea..."
for i in $(seq 1 40); do
  if curl -sf http://localhost:3000/api/healthz >/dev/null; then
    echo "[OK] gitea ready"
    break
  fi
  sleep 2
done

############################################
# GENERATE TOKEN (deterministic)
############################################
CID=$(docker ps --filter name=gitea -q)
TOKEN=$(docker exec "$CID" gitea actions generate-runner-token)
echo "$TOKEN" > "$SECRETS_DIR/runner_token"
chmod 600 "$SECRETS_DIR/runner_token"

############################################
# START RUNNER (last)
############################################
docker compose up -d act_runner

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea: http://localhost:3000"
echo "Grafana: http://localhost:3001"
echo "Prometheus: http://localhost:9090"
