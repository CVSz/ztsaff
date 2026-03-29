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
# gVisor AUTO-DETECT
############################################
RUNTIME="runc"
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
if test_gvisor; then RUNTIME="runsc"; fi
echo "[INFO] runtime=$RUNTIME"

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
# PROMETHEUS CONFIG (FIXED)
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
# DOCKER COMPOSE (FINAL)
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

  gitea:
    image: gitea/gitea:1.21-rootless
    depends_on:
      - postgres
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
      echo '[INFO] runner waiting for token...';
      for i in \$(seq 1 60); do
        if [ -s /run/secrets/runner_token ]; then
          echo '[OK] token found';
          break;
        fi;
        sleep 2;
      done;

      TOKEN=\$(cat /run/secrets/runner_token 2>/dev/null || echo '');

      if [ -z \"\$TOKEN\" ]; then
        echo '[ERROR] token missing → retry loop';
        while true; do sleep 10; done;
      fi;

      if [ ! -f /data/.runner ]; then
        echo '[INFO] registering runner...';
        act_runner register \
          --instance http://gitea:3000 \
          --token \$TOKEN \
          --name zgitea-runner \
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
# START
############################################
docker compose up -d

############################################
# GENERATE RUNNER TOKEN (DETERMINISTIC)
############################################
echo "[INFO] waiting gitea..."
until curl -sf http://localhost:3000/api/healthz >/dev/null; do
  sleep 2
done

CID=$(docker ps --filter name=gitea -q)

TOKEN=$(docker exec "$CID" gitea actions generate-runner-token)

echo "$TOKEN" > "$SECRETS_DIR/runner_token"
chmod 600 "$SECRETS_DIR/runner_token"

echo "[OK] token ready → restarting runner"
docker compose restart act_runner

############################################
# AI ENGINE (SAFE)
############################################
cat > ai-engine.sh <<'EOF'
#!/usr/bin/env bash
CPU=$(top -bn1 | awk '/Cpu/ {print 100 - $8}')
if (( ${CPU%.*} > 85 )); then
  TARGET=$(docker ps --format '{{.Names}}' | grep -vE 'postgres|gitea' | head -1)
  [[ -n "$TARGET" ]] && docker restart "$TARGET"
fi
EOF
chmod +x ai-engine.sh

############################################
# BACKUP
############################################
cat > backup.sh <<'EOF'
#!/usr/bin/env bash
TS=$(date +%F-%H%M)
DIR="$HOME/zgitea-installer/backup/$TS"
mkdir -p "$DIR"
docker exec $(docker ps --filter name=postgres -q) \
 pg_dump -U gitea gitea > "$DIR/db.sql"
EOF
chmod +x backup.sh

############################################
# SECRET ROTATION
############################################
cat > rotate-secret.sh <<'EOF'
#!/usr/bin/env bash
NEW=$(openssl rand -hex 32)
echo "$NEW" > /run/zgitea-installer/db_pass
docker exec $(docker ps --filter name=postgres -q) \
 psql -U gitea -d postgres -c "ALTER USER gitea WITH PASSWORD '$NEW';"
docker compose restart gitea act_runner
EOF
chmod +x rotate-secret.sh

############################################
# CRON SAFE
############################################
TMP=$(mktemp)
cat <<EOF > "$TMP"
*/2 * * * * ${BASE_DIR}/ai-engine.sh
0 */6 * * * ${BASE_DIR}/backup.sh
0 0 * * * ${BASE_DIR}/rotate-secret.sh
EOF
crontab "$TMP" || true
rm -f "$TMP"

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea: http://localhost:3000"
echo "Grafana: http://localhost:3001"
echo "Prometheus: http://localhost:9090"
