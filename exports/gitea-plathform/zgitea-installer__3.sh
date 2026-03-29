#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"
MON_DIR="${BASE_DIR}/monitoring"

############################################
# CONFIG (EDIT TELEGRAM HERE)
############################################
TG_BOT_TOKEN="YOUR_BOT_TOKEN"
TG_CHAT_ID="YOUR_CHAT_ID"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# CLEAN
############################################
docker ps -q | xargs -r docker stop
docker ps -aq | xargs -r docker rm -f
docker volume prune -f || true
docker network prune -f || true

############################################
# DOCKER INSTALL
############################################
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg cron jq bc
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

############################################
# TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=4M tmpfs "$SECRETS_DIR"

[[ -f "$SECRETS_DIR/db_pass" ]] || openssl rand -hex 32 > "$SECRETS_DIR/db_pass"
[[ -f "$SECRETS_DIR/secret" ]] || openssl rand -hex 32 > "$SECRETS_DIR/secret"
chmod 600 "$SECRETS_DIR"/*

############################################
# INIT
############################################
mkdir -p "$BASE_DIR"/{state,backup,snapshots,monitoring}
cd "$BASE_DIR"
echo "blue" > "$STATE_DIR/active"

############################################
# PROMETHEUS CONFIG
############################################
cat > monitoring/prometheus.yml <<'EOF'
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
# COMPOSE
############################################
cat > docker-compose.yml <<EOF
version: "3.9"

services:

  caddy:
    image: caddy:2.7-alpine
    ports: ["127.0.0.1:443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./state:/state
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: [no-new-privileges:true]

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

  gitea-blue:
    image: gitea/gitea:1.21-rootless
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

  gitea-green:
    image: gitea/gitea:1.21-rootless
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

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
EOF

############################################
# CADDY
############################################
cat > Caddyfile <<'EOF'
https://localhost {
    @blue expression `{file.read_string("/state/active")} == "blue"`
    @green expression `{file.read_string("/state/active")} == "green"`

    reverse_proxy @blue gitea-blue:3000
    reverse_proxy @green gitea-green:3000

    tls internal
}
EOF

############################################
# START
############################################
docker compose up -d

############################################
# TELEGRAM ALERT FUNCTION
############################################
cat > notify.sh <<EOF
#!/usr/bin/env bash
MSG="\$1"
curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
 -d chat_id="${TG_CHAT_ID}" \
 -d text="\$MSG" >/dev/null
EOF
chmod +x notify.sh

############################################
# SMART ANOMALY DETECTION
############################################
cat > anomaly.sh <<'EOF'
#!/usr/bin/env bash
CPU=$(curl -s http://localhost:9090/api/v1/query \
 --data-urlencode 'query=100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)' \
 | jq '.data.result[0].value[1]' | tr -d '"')

MEM=$(free | awk '/Mem/ {printf("%.0f"), $3/$2 * 100}')

BASE_FILE="/tmp/zgitea-baseline"

if [[ ! -f "$BASE_FILE" ]]; then
  echo "$CPU $MEM" > "$BASE_FILE"
  exit 0
fi

read BASE_CPU BASE_MEM < "$BASE_FILE"

CPU_DIFF=$(echo "$CPU - $BASE_CPU" | bc)
MEM_DIFF=$(echo "$MEM - $BASE_MEM" | bc)

if (( $(echo "$CPU_DIFF > 30" | bc -l) )); then
  bash notify.sh "⚠️ CPU anomaly: $CPU%"
fi

if (( $(echo "$MEM_DIFF > 30" | bc -l) )); then
  bash notify.sh "⚠️ Memory anomaly: $MEM%"
fi

echo "$CPU $MEM" > "$BASE_FILE"
EOF
chmod +x anomaly.sh

############################################
# HEALTH + ALERT
############################################
cat > healthcheck.sh <<'EOF'
#!/usr/bin/env bash
for c in $(docker ps --format '{{.Names}}'); do
  STATUS=$(docker inspect --format '{{.State.Status}}' $c)
  if [[ "$STATUS" != "running" ]]; then
    bash notify.sh "❌ Container down: $c"
    docker restart $c
  fi
done
EOF
chmod +x healthcheck.sh

############################################
# CRON
############################################
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/healthcheck.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/5 * * * * $BASE_DIR/anomaly.sh") | crontab -

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea → https://localhost"
echo "Grafana → http://localhost:3001"
echo "Prometheus → http://localhost:9090"
echo "Telegram alerts enabled"
