#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="./state"
mkdir -p "$STATE_DIR"

ACTIVE=$(cat "$STATE_DIR/active" 2>/dev/null || echo "blue")

if [[ "$ACTIVE" == "blue" ]]; then
  TARGET="green"
else
  TARGET="blue"
fi

echo "[INFO] current=$ACTIVE → deploying $TARGET"

# start target
docker compose -f docker-compose.bluegreen.yml up -d gitea-$TARGET

# wait health
echo "[INFO] waiting health..."
for i in {1..30}; do
  if curl -sf http://localhost:3000/api/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# switch traffic
echo "$TARGET" > "$STATE_DIR/active"
docker exec $(docker ps --filter name=caddy -q) \
  caddy reload --config /etc/caddy/Caddyfile

# stop old
docker stop gitea-$ACTIVE || true

echo "[OK] switched to $TARGET"
