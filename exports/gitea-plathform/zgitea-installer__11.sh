#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[FATAL] line $LINENO"; exit 1' ERR

PROJECT="zgitea-installer"
BASE_DIR="${HOME}/${PROJECT}"
SECRETS_DIR="/run/${PROJECT}"

############################################
# ROOT
############################################
if [[ $EUID -ne 0 ]]; then exec sudo bash "$0" "$@"; fi

############################################
# INSTALL
############################################
apt-get update
apt-get install -y curl jq cron ca-certificates

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

############################################
# TMPFS SECRETS
############################################
mkdir -p "$SECRETS_DIR"
mount | grep "$SECRETS_DIR" >/dev/null || \
  mount -t tmpfs -o size=8M tmpfs "$SECRETS_DIR"

gen_secret() {
  local f="$1"
  [[ -f "$f" ]] || openssl rand -hex 32 > "$f"
  chmod 600 "$f"
}

gen_secret "$SECRETS_DIR/db_pass"
gen_secret "$SECRETS_DIR/app_secret"

############################################
# DOCKER COMPOSE (NO ENV BUG)
############################################
cat > docker-compose.yml <<'EOF'
services:

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_USER: gitea
      POSTGRES_DB: gitea
      POSTGRES_PASSWORD_FILE: /run/secrets/db_pass
    volumes:
      - /run/zgitea-installer:/run/secrets:ro
      - postgres_data:/var/lib/postgresql/data

  gitea:
    image: gitea/gitea:1.21-rootless
    depends_on:
      - postgres
    volumes:
      - /run/zgitea-installer:/run/secrets:ro

  act_runner:
    image: gitea/act_runner:latest
    volumes:
      - /run/zgitea-installer:/run/secrets:ro
    entrypoint: ["/bin/sh","-c"]
    command: >
      "
      TOKEN=\$(cat /run/secrets/runner_token 2>/dev/null || echo '');
      if [ -z \"\$TOKEN\" ]; then
        echo '[WAIT] no runner token yet...';
        sleep 10;
      fi;

      if [ ! -f /data/.runner ]; then
        act_runner register \
          --instance http://gitea:3000 \
          --token \$TOKEN \
          --name zgitea-runner \
          --labels docker;
      fi;

      exec act_runner daemon;
      "

  prometheus:
    image: prom/prometheus
    ports: ["127.0.0.1:9090:9090"]

  grafana:
    image: grafana/grafana
    ports: ["127.0.0.1:3001:3000"]

volumes:
  postgres_data:
EOF

############################################
# START
############################################
docker compose up -d

############################################
# AUTO GENERATE RUNNER TOKEN
############################################
echo "[INFO] waiting gitea..."

until curl -sf http://localhost:3000/api/healthz >/dev/null; do
  sleep 2
done

CID=$(docker ps --filter name=gitea -q)

TOKEN=$(docker exec "$CID" \
  gitea actions generate-runner-token)

echo "$TOKEN" > "$SECRETS_DIR/runner_token"
chmod 600 "$SECRETS_DIR/runner_token"

echo "[OK] runner token generated"

############################################
# RESTART RUNNER (REGISTER NOW)
############################################
docker compose restart act_runner

############################################
# DONE
############################################
echo "[SUCCESS]"
echo "Gitea → http://localhost:3000"
