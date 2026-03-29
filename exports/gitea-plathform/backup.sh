#!/usr/bin/env bash
set -Eeuo pipefail

TS=$(date +%F-%H%M)
DIR="$HOME/zgitea-installer/backup/$TS"
mkdir -p "$DIR"

CID=$(docker ps --filter name=postgres -q)

docker exec "$CID" \
  pg_dump -U gitea -d gitea --format=custom \
  --no-owner --no-privileges \
  > "$DIR/db.dump"

# verify dump
if pg_restore -l "$DIR/db.dump" >/dev/null 2>&1; then
  bash notify.sh "✅ Backup OK: $TS"
else
  bash notify.sh "❌ Backup CORRUPTED: $TS"
fi
