#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
DOMAIN="${1:-git.zeaz.dev}"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"
STATE_DIR="${BASE_DIR}/state"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# PHASE 1 — CLEAN (SAFE)
############################################
docker ps -q | xargs -r docker stop
docker ps -aq | xargs -r docker rm -f
docker volume prune -f || true
docker network prune -f || true

############################################
# PHASE 2 — INSTALL DOCKER
############################################
if ! command -v docker >/dev/null; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg cron
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

############################################
# PHASE 3 — TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=4M tmpfs "$SECRETS_DIR"

[[ -f "$SECRETS_DIR/db_pass" ]] || openssl rand -hex 32 > "$SECRETS_DIR/db_pass"
[[ -f "$SECRETS_DIR/secret" ]] || openssl rand -hex 32 > "$SECRETS_DIR/secret"

chmod 600 "$SECRETS_DIR"/*

############################################
# PHASE 4 — INIT
############################################
mkdir -p "$BASE_DIR"/{state,backup,snapshots}
cd "$BASE_DIR"
[[ -f "$STATE_DIR/active" ]] || echo "blue" > "$STATE_DIR/active"

############################################
# PHASE 5 — COMPOSE
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
    command: ["postgres","-c","shared_buffers=128MB","-c","max_connections=50"]
    restart: unless-stopped

  gitea-blue:
    image: gitea/gitea:1.21-rootless
    environment: &env
      GITEA__database__DB_TYPE: postgres
      GITEA__database__HOST: postgres:5432
      GITEA__database__NAME: gitea
      GITEA__database__USER: gitea
      GITEA__database__PASSWD_FILE: /run/secrets/db_pass
      GITEA__security__SECRET_KEY__FILE: /run/secrets/secret
      GITEA__security__INTERNAL_TOKEN__FILE: /run/secrets/secret
      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__security__INSTALL_LOCK: "true"
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - gitea-blue:/var/lib/gitea
    mem_limit: 512m
    restart: unless-stopped

  gitea-green:
    image: gitea/gitea:1.21-rootless
    environment: *env
    volumes:
      - ${SECRETS_DIR}:/run/secrets:ro
      - gitea-green:/var/lib/gitea
    mem_limit: 512m
    restart: unless-stopped

volumes:
  db-data:
  gitea-blue:
  gitea-green:
EOF

############################################
# PHASE 6 — CADDY
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
# PHASE 7 — START
############################################
docker compose up -d postgres caddy gitea-blue

############################################
# PHASE 8 — AUTOMATION
############################################
cat > backup.sh <<'EOF'
#!/usr/bin/env bash
TS=$(date +%F-%H%M)
DIR="$HOME/zgitea-installer/backup/$TS"
mkdir -p "$DIR"

docker exec $(docker ps --filter name=postgres -q) \
 pg_dump -U gitea gitea > "$DIR/db.sql"

ls -dt $HOME/zgitea-installer/backup/* | tail -n +8 | xargs -r rm -rf
EOF

cat > autoheal.sh <<'EOF'
#!/usr/bin/env bash
for c in $(docker ps -q); do
 docker inspect --format '{{.State.Running}}' $c | grep true || docker restart $c
done
EOF

cat > snapshot.sh <<'EOF'
#!/usr/bin/env bash
TS=$(date +%F-%H%M)
tar -czf $HOME/zgitea-installer/snapshots/$TS.tar.gz docker-compose.yml Caddyfile
ls -dt $HOME/zgitea-installer/snapshots/* | tail -n +6 | xargs -r rm -f
EOF

chmod +x *.sh

(crontab -l 2>/dev/null; echo "0 */6 * * * $BASE_DIR/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/2 * * * * $BASE_DIR/autoheal.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * $BASE_DIR/snapshot.sh") | crontab -

############################################
# PHASE 9 — DEPLOY / ROLLBACK
############################################
cat > deploy.sh <<'EOF'
#!/usr/bin/env bash
STATE="./state/active"
ACTIVE=$(cat $STATE)
[[ "$ACTIVE" == "blue" ]] && TARGET="green" || TARGET="blue"

docker compose up -d gitea-$TARGET
sleep 5

echo "$TARGET" > $STATE
docker exec $(docker ps --filter name=caddy -q) caddy reload
docker stop gitea-$ACTIVE || true

echo "[OK] $ACTIVE → $TARGET"
EOF

cat > rollback.sh <<'EOF'
#!/usr/bin/env bash
STATE="./state/active"
ACTIVE=$(cat $STATE)
[[ "$ACTIVE" == "blue" ]] && TARGET="green" || TARGET="blue"

echo "$TARGET" > $STATE
docker exec $(docker ps --filter name=caddy -q) caddy reload

echo "[ROLLBACK] → $TARGET"
EOF

############################################
# PHASE 10 — CLOUDFLARE
############################################
cat > cloudflare.sh <<'EOF'
#!/usr/bin/env bash
docker run -d --name zgitea-cf \
 --restart unless-stopped \
 cloudflare/cloudflared \
 tunnel run --token YOUR_TOKEN
EOF

chmod +x deploy.sh rollback.sh cloudflare.sh

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Project: zgitea-installer"
echo "URL: https://localhost"
echo "Deploy: bash deploy.sh"
echo "Rollback: bash rollback.sh"
echo "Cloudflare: edit token + run cloudflare.sh"
