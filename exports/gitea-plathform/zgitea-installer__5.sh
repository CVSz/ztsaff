#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"

############################################
# CONFIG
############################################
TG_TOKEN="YOUR_TG_TOKEN"
TG_CHAT="YOUR_TG_CHAT"
LINE_TOKEN="YOUR_LINE_TOKEN"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# INIT
############################################
mkdir -p "$BASE_DIR"/{state,logs,ai}
cd "$BASE_DIR"
echo "blue" > "$STATE_DIR/active"

############################################
# DOCKER
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
# CORE STACK
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
EOF

docker compose up -d

############################################
# NOTIFY MULTI
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
# AI DECISION ENGINE
############################################
cat > ai-engine.sh <<'EOF'
#!/usr/bin/env bash
LOG="$HOME/zgitea-installer/logs/ai.log"

CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
MEM=$(free | awk '/Mem/ {print $3/$2 * 100}')

echo "$(date) CPU=$CPU MEM=$MEM" >> $LOG

####################################
# DECISION TREE
####################################

# CPU spike
if (( ${CPU%.*} > 85 )); then
  echo "[AI] CPU overload" >> $LOG

  docker stats --no-stream >> $LOG

  # auto-fix: restart heavy container
  TARGET=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}" | sort -k2 -nr | head -1 | awk '{print $1}')
  docker restart $TARGET

  bash rate.sh "🤖 AI FIX: Restarted $TARGET (CPU spike)"
fi

# Memory leak
if (( ${MEM%.*} > 90 )); then
  echo "[AI] Memory overload" >> $LOG

  docker system prune -f

  bash rate.sh "🤖 AI FIX: Memory cleanup triggered"
fi

####################################
# CONTAINER FAILURE
####################################
for c in $(docker ps --format '{{.Names}}'); do
  STATUS=$(docker inspect --format '{{.State.Status}}' $c)
  if [[ "$STATUS" != "running" ]]; then
    docker restart $c
    bash rate.sh "🤖 AI FIX: Restarted $c"
  fi
done

####################################
# SELF VERIFY
####################################
sleep 2
FAIL=$(docker ps --filter status=exited -q)

if [[ -n "$FAIL" ]]; then
  bash rate.sh "⚠️ AI WARNING: unresolved failure"
fi

EOF
chmod +x ai-engine.sh

############################################
# CRON AUTONOMOUS LOOP
############################################
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/ai-engine.sh") | crontab -

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Autonomous system ENABLED"
echo "AI loop: every 2 min"
echo "Alerts: Telegram + LINE"
echo "Logs: $BASE_DIR/logs/ai.log"
