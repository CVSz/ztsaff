#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"

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
  apt-get install -y ca-certificates curl gnupg cron
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
# COMPOSE (FULL STACK)
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
    read_only: true
    tmpfs: [/tmp]
    restart: unless-stopped

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped

  gitea-blue:
    image: gitea/gitea:1.21-rootless
    environment: &env
      GITEA__database__HOST: postgres:5432
      GITEA__database__PASSWD_FILE: /run/secrets/db_pass
      GITEA__security__SECRET_KEY__FILE: /run/secrets/secret
      GITEA__security__INTERNAL_TOKEN__FILE: /run/secrets/secret
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - gitea-blue:/var/lib/gitea

  gitea-green:
    image: gitea/gitea:1.21-rootless
    environment: *env
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - gitea-green:/var/lib/gitea

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
    pid: host
    network_mode: host

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    ports: ["127.0.0.1:8080:8080"]
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro

volumes:
  db-data:
  gitea-blue:
  gitea-green:
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
# AUTO TASKS
############################################
cat > backup.sh <<'EOF'
#!/usr/bin/env bash
TS=$(date +%F-%H%M)
mkdir -p $HOME/zgitea-installer/backup/$TS
docker exec $(docker ps --filter name=postgres -q) \
 pg_dump -U gitea gitea > $HOME/zgitea-installer/backup/$TS/db.sql
EOF

cat > autoheal.sh <<'EOF'
#!/usr/bin/env bash
for c in $(docker ps -q); do
 docker inspect --format '{{.State.Running}}' $c | grep true || docker restart $c
done
EOF

chmod +x *.sh
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/autoheal.sh") | crontab -

############################################
# DEPLOY
############################################
cat > deploy.sh <<'EOF'
STATE="./state/active"
ACTIVE=$(cat $STATE)
[[ "$ACTIVE" == "blue" ]] && TARGET="green" || TARGET="blue"

docker compose up -d gitea-$TARGET
sleep 5
echo "$TARGET" > $STATE
docker exec $(docker ps --filter name=caddy -q) caddy reload
docker stop gitea-$ACTIVE || true
EOF

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea: https://localhost"
echo "Grafana: http://localhost:3001"
echo "Prometheus: http://localhost:9090"
