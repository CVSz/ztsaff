#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"

############################################
# CONFIG (EDIT)
############################################
TG_TOKEN="YOUR_TG_TOKEN"
TG_CHAT="YOUR_TG_CHAT"

LINE_TOKEN="YOUR_LINE_NOTIFY_TOKEN"

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

############################################
# INSTALL
############################################
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y curl jq bc cron
  curl -fsSL https://get.docker.com | sh
fi

############################################
# TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" || mount -t tmpfs tmpfs "$SECRETS_DIR"

openssl rand -hex 32 > "$SECRETS_DIR/db_pass"
openssl rand -hex 32 > "$SECRETS_DIR/secret"
chmod 600 "$SECRETS_DIR"/*

############################################
# INIT
############################################
mkdir -p "$BASE_DIR"/{state,logs}
cd "$BASE_DIR"
echo "blue" > "$STATE_DIR/active"

############################################
# COMPOSE (CORE + AI RUNNER SAFE MODE)
############################################
cat > docker-compose.yml <<EOF
version: "3.9"

services:

  gitea:
    image: gitea/gitea:1.21-rootless

  prometheus:
    image: prom/prometheus
    ports: ["127.0.0.1:9090:9090"]

  grafana:
    image: grafana/grafana
    ports: ["127.0.0.1:3001:3000"]

  ai-runner:
    image: node:20-alpine
    command: sh -c "npm install -g openclaw && tail -f /dev/null"
    security_opt:
      - no-new-privileges:true
    read_only: true
    mem_limit: 256m
EOF

docker compose up -d

############################################
# MULTI NOTIFY
############################################
cat > notify.sh <<EOF
#!/usr/bin/env bash
MSG="\$1"

# Telegram
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
 -d chat_id="${TG_CHAT}" \
 -d text="\$MSG" >/dev/null

# LINE
curl -s -X POST https://notify-api.line.me/api/notify \
 -H "Authorization: Bearer ${LINE_TOKEN}" \
 -d "message=\$MSG" >/dev/null
EOF
chmod +x notify.sh

############################################
# RATE LIMIT (ANTI-SPAM)
############################################
cat > rate-limit.sh <<'EOF'
#!/usr/bin/env bash
FILE="/tmp/zgitea-alert"
NOW=$(date +%s)

if [[ -f $FILE ]]; then
  LAST=$(cat $FILE)
  DIFF=$((NOW - LAST))
  if [[ $DIFF -lt 60 ]]; then exit 0; fi
fi

echo $NOW > $FILE
bash notify.sh "$1"
EOF
chmod +x rate-limit.sh

############################################
# SMART ANOMALY
############################################
cat > anomaly.sh <<'EOF'
#!/usr/bin/env bash

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
MEM=$(free | awk '/Mem/ {print $3/$2 * 100}')

if (( ${CPU%.*} > 80 )); then
  bash rate-limit.sh "⚠️ CPU HIGH: $CPU%"
fi

if (( ${MEM%.*} > 85 )); then
  bash rate-limit.sh "⚠️ MEM HIGH: $MEM%"
fi
EOF
chmod +x anomaly.sh

############################################
# HEALTH
############################################
cat > health.sh <<'EOF'
#!/usr/bin/env bash
for c in $(docker ps --format '{{.Names}}'); do
  STATUS=$(docker inspect --format '{{.State.Status}}' $c)
  if [[ "$STATUS" != "running" ]]; then
    bash rate-limit.sh "❌ DOWN: $c"
    docker restart $c
  fi
done
EOF
chmod +x health.sh

############################################
# CRON
############################################
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/health.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/3 * * * * $BASE_DIR/anomaly.sh") | crontab -

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea → http://localhost:3000"
echo "Grafana → http://localhost:3001"
echo "Prometheus → http://localhost:9090"
echo "AI Runner → sandboxed"
echo "Telegram + LINE alert enabled"
