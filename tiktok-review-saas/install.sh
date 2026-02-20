#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "❌ docker-compose.yml not found in $ROOT_DIR"
  exit 1
fi

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

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

start_stack() {
  if docker compose version >/dev/null 2>&1; then
    $SUDO docker compose -f "$COMPOSE_FILE" up -d --build
  else
    $SUDO docker-compose -f "$COMPOSE_FILE" up -d --build
  fi
}

main() {
  echo "🚀 Automated installer starting..."
  install_docker
  install_compose_fallback

  $SUDO systemctl enable docker || true
  $SUDO systemctl start docker || true

  echo "🔧 Starting application stack..."
  start_stack

  echo "✅ Installation complete."
  echo "Tip: run 'docker ps' to confirm containers are healthy."
}

main "$@"
