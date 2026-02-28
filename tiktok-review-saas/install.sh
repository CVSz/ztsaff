#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "❌ docker-compose.yml not found in $ROOT_DIR"
  exit 1
fi

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

run_docker_cmd() {
  if docker compose version >/dev/null 2>&1; then
    $SUDO docker compose "$@"
  else
    $SUDO docker-compose "$@"
  fi
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    echo "✅ Docker already installed"
    return
  fi

  echo "Installing Docker..."
  $SUDO apt-get update
  $SUDO apt-get install -y ca-certificates curl gnupg lsb-release
  $SUDO install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

  $SUDO apt-get update
  $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_compose_fallback() {
  if docker compose version >/dev/null 2>&1; then
    echo "✅ docker compose plugin available"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    echo "✅ docker-compose binary available"
    return
  fi

  echo "Installing docker-compose fallback..."
  $SUDO apt-get update
  $SUDO apt-get install -y docker-compose
}

generate_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    echo "✅ .env already exists"
    return
  fi

  echo "🔐 Generating .env for final release..."
  if command -v openssl >/dev/null 2>&1; then
    JWT_SECRET_VALUE="$(openssl rand -hex 32)"
    ADMIN_KEY_VALUE="$(openssl rand -hex 16)"
  else
    JWT_SECRET_VALUE="$(date +%s%N | sha256sum | cut -d' ' -f1)"
    ADMIN_KEY_VALUE="$(date +%s%N | sha256sum | cut -c1-32)"
  fi

  cat > "$ENV_FILE" <<EOT
DATABASE_URL=postgresql://saas:saas@postgres:5432/tiktok_saas
JWT_SECRET=${JWT_SECRET_VALUE}
ADMIN_BOOTSTRAP_KEY=${ADMIN_KEY_VALUE}
FRONTEND_ORIGIN=http://localhost:3000
RELEASE_VERSION=1.0.0
RELEASE_NAME=Final Release
EOT

  echo "✅ Created $ENV_FILE"
  echo "Admin bootstrap key: ${ADMIN_KEY_VALUE}"
}

start_stack() {
  run_docker_cmd -f "$COMPOSE_FILE" up -d --build
}

main() {
  echo "🚀 Automated installer starting..."
  install_docker
  install_compose_fallback
  generate_env_file

  $SUDO systemctl enable docker || true
  $SUDO systemctl start docker || true

  echo "🔧 Starting application stack..."
  start_stack

  echo "✅ Installation complete."
  echo "Tip: run 'docker ps' to confirm containers are healthy."
}

main "$@"
