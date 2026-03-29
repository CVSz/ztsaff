#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

DOMAIN="${1:-git.zeaz.dev}"
BASE_DIR="${HOME}/zttato-local"
SECRETS_DIR="/run/zttato"

############################################
# ROOT CHECK
############################################
if [[ $EUID -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

############################################
# PHASE 1 — CLEAN
############################################
echo "[1] CLEAN"

docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f || true
docker network prune -f || true

apt-get purge -y docker docker.io containerd runc || true
rm -rf /var/lib/docker /var/lib/containerd
rm -rf /usr/local/lib/docker ~/.docker

k3d cluster delete --all 2>/dev/null || true

############################################
# PHASE 2 — INSTALL DOCKER
############################################
echo "[2] INSTALL DOCKER"

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release cron

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

############################################
# PHASE 3 — TMPFS SECRETS
############################################
echo "[3] SECRETS"

mkdir -p "$SECRETS_DIR"
mount -t tmpfs -o size=4M tmpfs "$SECRETS_DIR" || true

openssl rand -hex 32 > "$SECRETS_DIR/db_pass"
openssl rand -hex 32 > "$SECRETS_DIR/secret"

chmod 600 "$SECRETS_DIR"/*

############################################
# PHASE 4 — DEPLOY STACK (LOCALHOST)
############################################
echo "[4] DEPLOY"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

cat > docker-compose.yml <<EOF
version: "3.9"

services:
  caddy:
    image: caddy:2.7-alpine
    ports:
      - "127.0.0.1:443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt: [no-new-privileges:true]
    read_only: true
    tmpfs: [/tmp]
    mem_limit: 128m
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
    mem_limit: 256m
    restart: unless-stopped

  gitea:
    image: gitea/gitea:1.21-rootless
    depends_on: [postgres]
    environment:
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
      - gitea-data:/var/lib/gitea
    cap_drop: [ALL]
    security_opt: [no-new-privileges:true]
    read_only: true
    tmpfs: [/tmp,/run]
    mem_limit: 512m
    restart: unless-stopped

volumes:
  db-data:
  gitea-data:
EOF

cat > Caddyfile <<EOF
https://localhost {
    reverse_proxy gitea:3000
    tls internal
}
EOF

docker compose up -d

############################################
# PHASE 5 — BACKUP + SNAPSHOT + AUTOHEAL
############################################
echo "[5] AUTOMATION"

cat > ${BASE_DIR}/backup.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
TS=$(date +%Y%m%d-%H%M%S)
DIR="$HOME/zttato-local/backup/$TS"
mkdir -p "$DIR"

docker exec $(docker ps --filter name=postgres -q) \
  pg_dump -U gitea gitea > "$DIR/db.sql"

tar -czf "$DIR/gitea.tar.gz" -C "$HOME/zttato-local" gitea-data 2>/dev/null || true

ls -dt $HOME/zttato-local/backup/* | tail -n +8 | xargs -r rm -rf
EOF

chmod +x ${BASE_DIR}/backup.sh

cat > ${BASE_DIR}/autoheal.sh <<'EOF'
#!/usr/bin/env bash
for c in $(docker ps --format '{{.Names}}'); do
  s=$(docker inspect --format '{{.State.Status}}' $c)
  if [[ "$s" != "running" ]]; then
    docker restart $c
  fi
done
EOF

chmod +x ${BASE_DIR}/autoheal.sh

cat > ${BASE_DIR}/snapshot.sh <<'EOF'
#!/usr/bin/env bash
TS=$(date +%Y%m%d-%H%M%S)
DIR="$HOME/zttato-local/snapshots"
mkdir -p "$DIR"
tar -czf "$DIR/snap-$TS.tar.gz" -C "$HOME/zttato-local" docker-compose.yml Caddyfile
ls -dt $DIR/* | tail -n +6 | xargs -r rm -f
EOF

chmod +x ${BASE_DIR}/snapshot.sh

(crontab -l 2>/dev/null; echo "0 */6 * * * ${BASE_DIR}/backup.sh") | crontab -
(crontab -l 2>/dev/null; echo "*/2 * * * * ${BASE_DIR}/autoheal.sh") | crontab -
(crontab -l 2>/dev/null; echo "0 3 * * * ${BASE_DIR}/snapshot.sh") | crontab -

############################################
# PHASE 6 — CLOUDFLARE (OPTIONAL)
############################################
cat > ${BASE_DIR}/cloudflare.sh <<EOF
#!/usr/bin/env bash
docker run -d --name cf-tunnel \\
  --restart unless-stopped \\
  cloudflare/cloudflared:latest \\
  tunnel run --token YOUR_TOKEN
EOF

chmod +x ${BASE_DIR}/cloudflare.sh

############################################
# VERIFY
############################################
echo "[VERIFY]"
docker ps
echo "[OK] https://localhost"
echo "[INFO] Cloudflare: edit token then run cloudflare.sh"
