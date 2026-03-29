#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

BASE_DIR="${HOME}/zttato-v10"
DOMAIN="${1:-gitea.local}"
umask 077

mkdir -p "$BASE_DIR"/{vault,spire,data}
cd "$BASE_DIR"

############################################
# 1. TMPFS MEMORY SECRETS (REAL)
############################################
sudo mkdir -p /run/zttato
sudo mount -t tmpfs -o size=4M tmpfs /run/zttato || true

openssl rand -hex 32 | sudo tee /run/zttato/db_pass >/dev/null
openssl rand -hex 32 | sudo tee /run/zttato/gitea_secret >/dev/null

sudo chmod 600 /run/zttato/*

############################################
# 2. MINIMAL SAFE SECCOMP (DERIVED)
############################################
cat > seccomp.json << 'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    { "names": ["read","write","exit","exit_group","futex","clock_gettime","nanosleep","epoll_wait","epoll_ctl","rt_sigreturn","rt_sigaction","sigaltstack","brk","mmap","munmap","close","openat","fcntl","stat","fstat","lseek","getdents64","getpid","gettid","clone","execve","socket","connect","accept","bind","listen","setsockopt","prlimit64"], "action": "SCMP_ACT_ALLOW" }
  ]
}
EOF

############################################
# 3. CADDY (AUTO TLS)
############################################
cat > Caddyfile << EOF
{
    email admin@${DOMAIN}
}

https://${DOMAIN} {
    reverse_proxy gitea:3000
    encode zstd gzip

    tls {
        protocols tls1.3
    }

    header {
        Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
        X-Frame-Options "DENY"
        X-Content-Type-Options "nosniff"
        Content-Security-Policy "default-src 'self'; frame-ancestors 'none';"
    }
}
EOF

############################################
# 4. DOCKER COMPOSE (REAL SEGMENTED)
############################################
cat > docker-compose.yml << 'EOF'
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
    security_opt:
      - no-new-privileges:true
      - seccomp=./seccomp.json
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
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
      - type: bind
        source: /run/zttato
        target: /run/secrets
        read_only: true
      - db-data:/var/lib/postgresql/data
    command:
      - postgres
      - -c ssl=off
      - -c password_encryption=scram-sha-256
    security_opt:
      - no-new-privileges:true
    networks: [db]

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

      GITEA__security__SECRET_KEY__FILE: /run/secrets/gitea_secret
      GITEA__security__INTERNAL_TOKEN__FILE: /run/secrets/gitea_secret
      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__security__INSTALL_LOCK: "true"

    volumes:
      - type: bind
        source: /run/zttato
        target: /run/secrets
        read_only: true
      - gitea-data:/var/lib/gitea

    security_opt:
      - no-new-privileges:true
      - seccomp=./seccomp.json

    cap_drop: [ALL]
    networks: [app, db]
    read_only: true
    tmpfs:
      - /tmp
      - /run

volumes:
  db-data:
  gitea-data:
EOF

############################################
# 5. NFTABLES FIREWALL (HOST ZERO-TRUST)
############################################
sudo nft flush ruleset || true

sudo nft add table inet zttato
sudo nft add chain inet zttato input { type filter hook input priority 0 \; policy drop \; }
sudo nft add chain inet zttato output { type filter hook output priority 0 \; policy drop \; }

# allow loopback
sudo nft add rule inet zttato input iif lo accept
sudo nft add rule inet zttato output oif lo accept

# allow HTTPS inbound/outbound
sudo nft add rule inet zttato input tcp dport 443 accept
sudo nft add rule inet zttato output tcp dport 443 accept

############################################
# 6. RUN
############################################
docker compose up -d

echo "[OK] v10 Ultra Hardened running → https://${DOMAIN}"
