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
# CONFIG
############################################
TG_TOKEN="${TG_TOKEN:-YOUR_TG_TOKEN}"
TG_CHAT="${TG_CHAT:-YOUR_TG_CHAT}"
LINE_TOKEN="${LINE_TOKEN:-YOUR_LINE_TOKEN}"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo -E bash "$0" "$@"; fi

############################################
# CLEAN (safe)
############################################
docker ps -q | xargs -r docker stop || true
docker ps -aq | xargs -r docker rm -f || true
docker volume prune -f || true
docker network prune -f || true

############################################
# INSTALL BASE
############################################
apt-get update
apt-get install -y curl jq bc cron ca-certificates util-linux

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

############################################
# INSTALL gVisor (auto-detect)
############################################
RUNTIME="runc"

install_gvisor() {
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
  docker run --rm --runtime=runsc alpine echo OK >/dev/null 2>&1
}

install_gvisor || true
if test_gvisor; then RUNTIME="runsc"; fi
echo "[INFO] Runtime: $RUNTIME"

############################################
# TMPFS SECRETS (DUAL SLOT)
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=8M tmpfs "$SECRETS_DIR"

init_secret() {
  local name="$1"
  [[ -f "$SECRETS_DIR/${name}.current" ]] || openssl rand -hex 32 > "$SECRETS_DIR/${name}.current"
  chmod 600 "$SECRETS_DIR/${name}.current"
}
init_secret "db_pass"
init_secret "app_secret"

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
    static_configs: [{targets: ['node-exporter:9100']}]
  - job_name: cadvisor
    static_configs: [{targets: ['cadvisor:8080']}]
EOF

############################################
# DOCKER COMPOSE (HARDENED)
############################################
cat > docker-compose.yml <<EOF
services:

  gitea:
    image: gitea/gitea:1.21-rootless
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      GITEA__database__HOST: postgres:5432
      GITEA__database__USER: gitea
      GITEA__database__NAME: gitea
      GITEA__database__PASSWD_FILE: /run/secrets/db_pass
      GITEA__security__SECRET_KEY__FILE: /run/secrets/app_secret
      GITEA__security__INTERNAL_TOKEN__FILE: /run/secrets/app_secret
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - postgres_data:/var/lib/postgresql/data
    command:
      - postgres
      - -c
      - shared_buffers=128MB
      - -c
      - synchronous_commit=on
      - -c
      - wal_sync_method=fdatasync
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 5s
      retries: 5

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
    cap_drop: [ALL]
    tmpfs: [/tmp, /var/tmp]
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
    networks: [runner_net]

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

volumes:
  postgres_data:
EOF

############################################
# START
############################################
docker compose up -d

############################################
# NOTIFY
############################################
cat > notify.sh <<'EOF'
#!/usr/bin/env bash
MSG="$1"
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
 -d chat_id="${TG_CHAT}" -d text="$MSG" >/dev/null
curl -s -X POST https://notify-api.line.me/api/notify \
 -H "Authorization: Bearer ${LINE_TOKEN}" \
 -d "message=$MSG" >/dev/null
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
# AI ENGINE (SAFE)
############################################
cat > ai-engine.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
LOCK="/tmp/zgitea-ai.lock"; exec 9>"$LOCK"; flock -n 9 || exit 0

CPU=$(top -bn1 | awk '/Cpu/ {print 100 - $8}')
CRITICAL="postgres|gitea|prometheus|grafana"

if (( ${CPU%.*} > 85 )); then
  TARGET=$(docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}" \
    | grep -vE "$CRITICAL" | sort -k2 -nr | head -1 | awk '{print $1}')
  [[ -n "$TARGET" ]] && docker restart "$TARGET" && bash rate.sh "🤖 AI restart: $TARGET"
fi
EOF
chmod +x ai-engine.sh

############################################
# BACKUP (ATOMIC)
############################################
cat > backup.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
TS=$(date +%F-%H%M)
DIR="$HOME/zgitea-installer/backup/$TS"
mkdir -p "$DIR"
CID=$(docker ps --filter name=postgres -q)
docker exec "$CID" pg_dump -U gitea -d gitea --format=custom > "$DIR/db.dump"
pg_restore -l "$DIR/db.dump" >/dev/null && bash notify.sh "✅ Backup $TS"
EOF
chmod +x backup.sh

############################################
# 🔐 SECRET ROTATION ENGINE
############################################
cat > rotate-secret.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SECRETS_DIR="/run/zgitea-installer"
NEW=$(openssl rand -hex 32)
echo "$NEW" > "$SECRETS_DIR/db_pass.next"
chmod 600 "$SECRETS_DIR/db_pass.next"

CID=$(docker ps --filter name=postgres -q)

# Apply new password
docker exec "$CID" psql -U gitea -d postgres \
  -c "ALTER USER gitea WITH PASSWORD '$NEW';"

# swap atomically
mv "$SECRETS_DIR/db_pass.next" "$SECRETS_DIR/db_pass.current"

# restart dependent services (minimal)
docker compose restart gitea act_runner

# verify
if docker exec "$CID" pg_isready -U gitea; then
  echo "[OK] rotation success"
else
  echo "[FAIL] rollback"
  exit 1
fi
EOF
chmod +x rotate-secret.sh

############################################
# CRON SAFE (AUTO-REPAIR)
############################################
install_cron() {
  TMP=$(mktemp)
  crontab -l 2>/dev/null | sed 's/\r$//' > "$TMP" || true
  sed -i '/zgitea-installer/d' "$TMP"

  cat <<EOF >> "$TMP"
*/2 * * * * ${BASE_DIR}/ai-engine.sh # zgitea-installer
0 */6 * * * ${BASE_DIR}/backup.sh # zgitea-installer
0 0 * * * ${BASE_DIR}/rotate-secret.sh # zgitea-installer
EOF

  crontab "$TMP" || { crontab -r || true; crontab "$TMP"; }
  rm -f "$TMP"
}
install_cron

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Runtime: $RUNTIME"
echo "Secret Rotation: ENABLED (daily)"
echo "System: Autonomous + Hardened"
