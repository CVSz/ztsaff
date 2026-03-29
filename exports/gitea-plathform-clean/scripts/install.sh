#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="$HOME/zttato-gitea"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

docker compose up -d
