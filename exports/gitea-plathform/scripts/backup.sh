#!/usr/bin/env bash
set -Eeuo pipefail

TS=$(date +%F-%H%M)
DIR="$HOME/backups/$TS"
mkdir -p "$DIR"

docker exec $(docker ps --filter name=postgres -q) \
  pg_dump -U $POSTGRES_USER $POSTGRES_DB > "$DIR/db.sql"
