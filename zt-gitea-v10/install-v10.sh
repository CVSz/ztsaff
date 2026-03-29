#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] install failed at line $LINENO" >&2; exit 1' ERR

BASE_DIR="${BASE_DIR:-$HOME/zttato-v10}"
DOMAIN="${1:-gitea.local}"
EMAIL="${EMAIL:-admin@${DOMAIN}}"
FORCE="${FORCE:-false}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  }
}

log() { echo ">>> $*"; }

require_cmd docker
require_cmd openssl
require_cmd sudo
require_cmd mount
require_cmd nft

if [[ "$FORCE" != "true" && -d "$BASE_DIR" ]]; then
  echo "[ERROR] $BASE_DIR already exists. Set FORCE=true to overwrite." >&2
  exit 1
fi

umask 077
mkdir -p "$BASE_DIR"/{templates,scripts,data}
cd "$BASE_DIR"

log "Preparing tmpfs-backed secret directory"
sudo mkdir -p /run/zttato
if ! mount | grep -q 'on /run/zttato type tmpfs'; then
  sudo mount -t tmpfs -o size=4M,mode=0700 tmpfs /run/zttato
fi

openssl rand -hex 32 | sudo tee /run/zttato/db_pass >/dev/null
openssl rand -hex 32 | sudo tee /run/zttato/gitea_secret >/dev/null
sudo chmod 600 /run/zttato/db_pass /run/zttato/gitea_secret

log "Writing hardened seccomp profile"
cat > seccomp.json <<'JSON'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "archMap": [
    {
      "architecture": "SCMP_ARCH_X86_64",
      "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"]
    }
  ],
  "syscalls": [
    {
      "names": [
        "accept","accept4","access","arch_prctl","bind","brk","capget","capset","chdir","clock_gettime",
        "clone","clone3","close","connect","dup","dup2","dup3","epoll_create","epoll_create1","epoll_ctl",
        "epoll_pwait","epoll_wait","eventfd","eventfd2","execve","execveat","exit","exit_group","faccessat",
        "fchmod","fchmodat","fchown","fchownat","fcntl","fdatasync","flock","fork","fstat","fstatfs","fsync",
        "ftruncate","futex","getcwd","getdents64","getegid","geteuid","getgid","getpeername","getpgid","getpgrp",
        "getpid","getppid","getpriority","getrandom","getrlimit","getsid","getsockname","getsockopt","gettid","getuid",
        "ioctl","kill","listen","lseek","lstat","madvise","membarrier","mkdir","mkdirat","mknod","mmap","mount",
        "mprotect","munmap","nanosleep","newfstatat","open","openat","pipe","pipe2","poll","ppoll","prctl",
        "pread64","preadv","prlimit64","pselect6","pwrite64","pwritev","read","readlink","readlinkat","recvfrom",
        "recvmmsg","recvmsg","rename","renameat","restart_syscall","rmdir","rt_sigaction","rt_sigprocmask","rt_sigreturn",
        "sched_getaffinity","sched_yield","seccomp","select","sendfile","sendmmsg","sendmsg","sendto","set_robust_list",
        "set_tid_address","setgid","setgroups","sethostname","setitimer","setpgid","setpriority","setsid","setsockopt",
        "setuid","shutdown","sigaltstack","socket","socketpair","stat","statfs","symlink","symlinkat","tgkill","time",
        "tkill","truncate","umask","uname","unlink","unlinkat","wait4","waitid","write","writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
JSON

log "Writing Caddy configuration"
cat > Caddyfile <<EOF2
{
    email ${EMAIL}
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
        Referrer-Policy "strict-origin-when-cross-origin"
        Permissions-Policy "camera=(), microphone=(), geolocation=()"
    }
}
EOF2

log "Writing docker-compose"
cat > docker-compose.yml <<'YAML'
version: "3.9"

networks:
  edge:
  app:
    internal: true
  db:
    internal: true

services:
  caddy:
    image: caddy:2.8-alpine
    container_name: zt-caddy
    restart: unless-stopped
    ports:
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    security_opt:
      - no-new-privileges:true
      - seccomp=./seccomp.json
    cap_drop: ["ALL"]
    cap_add: ["NET_BIND_SERVICE"]
    networks: ["edge", "app"]
    read_only: true
    tmpfs: ["/tmp"]
    mem_limit: 256m
    pids_limit: 128

  postgres:
    image: postgres:16-alpine
    container_name: zt-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - type: bind
        source: /run/zttato
        target: /run/secrets
        read_only: true
      - pg-data:/var/lib/postgresql/data
    command:
      - postgres
      - -c
      - password_encryption=scram-sha-256
      - -c
      - log_connections=on
      - -c
      - log_disconnections=on
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea -d gitea"]
      interval: 10s
      timeout: 5s
      retries: 10
    networks: ["db"]
    mem_limit: 512m
    pids_limit: 256

  gitea:
    image: gitea/gitea:1.22-rootless
    container_name: zt-gitea
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      GITEA__database__DB_TYPE: postgres
      GITEA__database__HOST: postgres:5432
      GITEA__database__NAME: gitea
      GITEA__database__USER: gitea
      GITEA__database__PASSWD_FILE: /run/secrets/db_pass
      GITEA__security__SECRET_KEY__FILE: /run/secrets/gitea_secret
      GITEA__security__INTERNAL_TOKEN__FILE: /run/secrets/gitea_secret
      GITEA__security__INSTALL_LOCK: "true"
      GITEA__service__DISABLE_REGISTRATION: "true"
      GITEA__service__REGISTER_EMAIL_CONFIRM: "true"
      GITEA__actions__ENABLED: "false"
    volumes:
      - type: bind
        source: /run/zttato
        target: /run/secrets
        read_only: true
      - gitea-data:/var/lib/gitea
    security_opt:
      - no-new-privileges:true
      - seccomp=./seccomp.json
    cap_drop: ["ALL"]
    networks: ["app", "db"]
    read_only: true
    tmpfs: ["/tmp", "/run"]
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "-", "http://localhost:3000/api/healthz"]
      interval: 15s
      timeout: 5s
      retries: 10
    mem_limit: 1g
    pids_limit: 256

volumes:
  pg-data:
  gitea-data:
  caddy-data:
  caddy-config:
YAML

log "Applying nftables baseline rules"
sudo nft flush ruleset || true
sudo nft add table inet zttato
sudo nft 'add chain inet zttato input { type filter hook input priority 0; policy drop; }'
sudo nft 'add chain inet zttato output { type filter hook output priority 0; policy drop; }'
sudo nft add rule inet zttato input iif lo accept
sudo nft add rule inet zttato output oif lo accept
sudo nft add rule inet zttato input ct state established,related accept
sudo nft add rule inet zttato output ct state established,related accept
sudo nft add rule inet zttato input tcp dport 443 accept
sudo nft add rule inet zttato output tcp dport 443 accept
sudo nft add rule inet zttato output udp dport 53 accept
sudo nft add rule inet zttato output tcp dport 53 accept

log "Starting stack"
docker compose up -d

log "Done. Open https://${DOMAIN}"
