#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

DOMAIN="${1:-gitea.local}"
BASE_DIR="${HOME}/zttato-v10"

############################################
# PRECHECK
############################################
if [[ $EUID -ne 0 ]]; then
  echo "[INFO] switching to sudo..."
  exec sudo bash "$0" "$@"
fi

echo "[PHASE 0] ENV CHECK"
command -v docker >/dev/null && echo "[INFO] docker exists (will purge)"

############################################
# PHASE 1 — FULL CLEAN
############################################
echo "[PHASE 1] CLEAN SYSTEM"

docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker rmi -f $(docker images -aq) 2>/dev/null || true
docker volume rm $(docker volume ls -q) 2>/dev/null || true
docker network rm $(docker network ls -q | grep -v bridge | grep -v host | grep -v none) 2>/dev/null || true

apt-get purge -y docker docker-engine docker.io containerd runc || true
rm -rf /var/lib/docker /var/lib/containerd

rm -rf /usr/local/lib/docker
rm -rf ~/.docker

k3d cluster delete --all 2>/dev/null || true

apt-get autoremove -y
apt-get autoclean -y

rm -rf /tmp/*
journalctl --vacuum-time=1d || true

iptables -F || true
nft flush ruleset || true

############################################
# PHASE 2 — INSTALL DOCKER (CLEAN)
############################################
echo "[PHASE 2] INSTALL DOCKER"

apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

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
# PHASE 3 — HARDEN HOST
############################################
echo "[PHASE 3] HARDEN HOST"

sysctl -w net.ipv4.ip_forward=0
sysctl -w kernel.unprivileged_userns_clone=0

cat > /etc/sysctl.d/99-zttato.conf <<EOF
net.ipv4.ip_forward=0
kernel.unprivileged_userns_clone=0
EOF

chmod 660 /var/run/docker.sock

# nftables zero-trust baseline
nft add table inet zttato || true

nft add chain inet zttato input { type filter hook input priority 0 \; policy drop \; } || true
nft add chain inet zttato output { type filter hook output priority 0 \; policy drop \; } || true

nft add rule inet zttato input iif lo accept || true
nft add rule inet zttato output oif lo accept || true

nft add rule inet zttato input tcp dport 443 accept || true
nft add rule inet zttato output tcp dport 443 accept || true

############################################
# PHASE 4 — TMPFS SECRETS
############################################
echo "[PHASE 4] SECRETS"

mkdir -p /run/zttato
mount -t tmpfs -o size=4M tmpfs /run/zttato || true

openssl rand -hex 32 > /run/zttato/db_pass
openssl rand -hex 32 > /run/zttato/secret

chmod 600 /run/zttato/*

############################################
# PHASE 5 — DEPLOY GITEA v10
############################################
echo "[PHASE 5] DEPLOY"

mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

cat > docker-compose.yml <<EOF
version: "3.9"

networks:
  edge:
  app:
    internal: true
  db:
    internal: true

services:

  caddy:
    image: caddy:2.7-alpine
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    security_opt:
      - no-new-privileges:true
    networks: [edge, app]
    read_only: true
    tmpfs: [/tmp]

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - /run/zttato:/run/secrets:ro
      - db-data:/var/lib/postgresql/data
    networks: [db]
    security_opt:
      - no-new-privileges:true

  gitea:
    image: gitea/gitea:1.21-rootless
    depends_on:
      - postgres
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
      - /run/zttato:/run/secrets:ro
      - gitea-data:/var/lib/gitea

    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true
    networks: [app, db]
    read_only: true
    tmpfs:
      - /tmp
      - /run

volumes:
  db-data:
  gitea-data:
EOF

cat > Caddyfile <<EOF
https://${DOMAIN} {
    reverse_proxy gitea:3000
    tls internal
}
EOF

docker compose up -d

############################################
# FINAL CHECK
############################################
echo "[VERIFY]"
docker ps
ss -tulpen | grep 443 || true

echo "[SUCCESS] https://${DOMAIN}"
