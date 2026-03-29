#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"
LOG_DIR="${BASE_DIR}/logs"
MON_DIR="${BASE_DIR}/monitoring"

############################################
# CONFIG (SET TOKENS)
############################################
TG_TOKEN="YOUR_TG_TOKEN"
TG_CHAT="YOUR_TG_CHAT"
LINE_TOKEN="YOUR_LINE_TOKEN"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# CLEAN
############################################
docker ps -q | xargs -r docker stop || true
docker ps -aq | xargs -r docker rm -f || true
docker volume prune -f || true
docker network prune -f || true

############################################
# INSTALL BASE
############################################
apt-get update
apt-get install -y curl jq bc cron ca-certificates

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

############################################
# INSTALL gVisor (runsc + shim)
############################################
RUNTIME="runc"

install_gvisor() {
  echo "[INFO] Installing gVisor..."
  curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/runsc \
    -o /usr/local/bin/runsc || return 1
  curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/containerd-shim-runsc-v1 \
    -o /usr/local/bin/containerd-shim-runsc-v1 || return 1
  chmod +x /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1

  cat > /etc/docker/daemon.json <<EOF
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc"
    }
  }
}
EOF

  systemctl restart docker
}

test_gvisor() {
  echo "[INFO] Testing gVisor runtime..."
  if docker run --rm --runtime=runsc alpine echo OK >/dev/null 2>&1; then
    echo "[OK] gVisor works"
    return 0
  else
    echo "[WARN] gVisor failed → fallback to runc"
    return 1
  fi
}

install_gvisor || true
if test_gvisor; then
  RUNTIME="runsc"
fi

echo "[INFO] Selected runtime: $RUNTIME"

############################################
# TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=4M tmpfs "$SECRETS_DIR"

openssl rand -hex 32 > "$SECRETS_DIR/db_pass"
openssl rand -hex 32 > "$SECRETS_DIR/secret"
chmod 600 "$SECRETS_DIR"/*

############################################
# INIT
############################################
mkdir -p "$BASE_DIR"/{state,logs,backup,snapshots,monitoring}
cd "$BASE_DIR"
echo "blue" > "$STATE_DIR/active"

############################################
# PROMETHEUS CONFIG
############################################
cat > "$MON_DIR/prometheus.yml" <<'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
EOF

############################################
# DOCKER COMPOSE (dynamic runtime inject)
############################################
cat > docker-compose.yml <<EOF
services:

  gitea:
    image: gitea/gitea:1.21-rootless
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

  act_runner:
    image: gitea/act_runner:latest
    environment:
      GITEA_INSTANCE_URL: http://gitea:3000
      GITEA_RUNNER_REGISTRATION_TOKEN: REGISTER_TOKEN
    $( [[ "$RUNTIME" == "runsc" ]] && echo "runtime: runsc" )
    read_only: true
    mem_limit: 512m
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    tmpfs:
      - /tmp
    networks:
      - runner_net

  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
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

networks:
  runner_net:
    internal: true
EOF

############################################
# START
############################################
docker compose up -d

############################################
# NOTIFY (TELEGRAM + LINE)
############################################
cat > notify.sh <<EOF
#!/usr/bin/env bash
MSG="\$1"

curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
 -d chat_id="${TG_CHAT}" -d text="\$MSG" >/dev/null

curl -s -X POST https://notify-api.line.me/api/notify \
 -H "Authorization: Bearer ${LINE_TOKEN}" \
 -d "message=\$MSG" >/dev/null
EOF
chmod +x notify.sh

############################################
# RATE LIMIT
############################################
cat > rate.sh <<'EOF'
FILE="/tmp/zgitea-rate"
NOW=$(date +%s)
[[ -f $FILE ]] && LAST=$(cat $FILE) || LAST=0
(( NOW - LAST < 60 )) && exit 0
echo $NOW > $FILE
bash notify.sh "$1"
EOF
chmod +x rate.sh

############################################
# AI ENGINE
############################################
cat > ai-engine.sh <<'EOF'
#!/usr/bin/env bash

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
MEM=$(free | awk '/Mem/ {print $3/$2 * 100}')

if (( ${CPU%.*} > 85 )); then
  TARGET=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}" | sort -k2 -nr | head -1 | awk '{print $1}')
  docker restart $TARGET
  bash rate.sh "🤖 CPU FIX: $TARGET"
fi

if (( ${MEM%.*} > 90 )); then
  docker system prune -f
  bash rate.sh "🤖 MEM CLEAN"
fi

for c in $(docker ps --format '{{.Names}}'); do
  STATUS=$(docker inspect --format '{{.State.Status}}' $c)
  if [[ "$STATUS" != "running" ]]; then
    docker restart $c
    bash rate.sh "🤖 RESTART: $c"
  fi
done
EOF
chmod +x ai-engine.sh

############################################
# BACKUP
############################################
cat > backup.sh <<'EOF'
TS=$(date +%F-%H%M)
DIR="$HOME/zgitea-installer/backup/$TS"
mkdir -p "$DIR"

docker exec $(docker ps --filter name=postgres -q) \
 pg_dump -U gitea gitea > "$DIR/db.sql"
EOF
chmod +x backup.sh

############################################
# CRON
############################################
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/ai-engine.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 */6 * * * $BASE_DIR/backup.sh") | crontab -

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Runtime: $RUNTIME"
echo "Gitea → http://localhost:3000"
echo "Grafana → http://localhost:3001"
echo "Prometheus → http://localhost:9090"
echo "AI + Alert → ENABLED"
