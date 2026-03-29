#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

BASE_DIR="${HOME}/zttato-local"
umask 077

############################################
# PHASE 1 — CLEAN (SAFE MINIMAL)
############################################
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f || true
docker network prune -f || true

############################################
# PHASE 2 — TMPFS SECRETS
############################################
mkdir -p /run/zttato
mount -t tmpfs -o size=2M tmpfs /run/zttato || true

openssl rand -hex 32 > /run/zttato/db_pass
openssl rand -hex 32 > /run/zttato/secret

chmod 600 /run/zttato/*

############################################
# PHASE 3 — DEPLOY (LOCALHOST ONLY)
############################################
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

cat > docker-compose.yml << 'EOF'
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
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs: [/tmp]
    mem_limit: 128m

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - /run/zttato:/run/secrets:ro
      - db-data:/var/lib/postgresql/data
    command:
      - postgres
      - -c shared_buffers=128MB
      - -c max_connections=50
    security_opt:
      - no-new-privileges:true
    mem_limit: 256m

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
    read_only: true
    tmpfs:
      - /tmp
      - /run
    mem_limit: 512m

volumes:
  db-data:
  gitea-data:
EOF

############################################
# PHASE 4 — CADDY LOCAL TLS
############################################
cat > Caddyfile << 'EOF'
https://localhost {
    reverse_proxy gitea:3000
    tls internal
}
EOF

############################################
# PHASE 5 — RUN
############################################
docker compose up -d

############################################
# VERIFY
############################################
echo "[CHECK]"
docker ps
curl -sk https://localhost | head -n 5

echo "[OK] https://localhost"
