#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="./state"
ACTIVE=$(cat "$STATE_DIR/active")

if [[ "$ACTIVE" == "blue" ]]; then
  TARGET="green"
else
  TARGET="blue"
fi

echo "$TARGET" > "$STATE_DIR/active"

docker exec $(docker ps --filter name=caddy -q) \
  caddy reload --config /etc/caddy/Caddyfile

echo "[ROLLBACK] now active=$TARGET"
