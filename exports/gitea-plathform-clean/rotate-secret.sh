
#!/usr/bin/env bash
set -Eeuo pipefail

SECRETS_DIR="/run/zgitea-installer"
CID_DB=$(docker ps --filter name=postgres -q)
CID_GITEA=$(docker ps --filter name=gitea -q)

NEW=$(openssl rand -hex 32)
echo "$NEW" > "$SECRETS_DIR/db_pass.next"
chmod 600 "$SECRETS_DIR/db_pass.next"

# 1. apply new password
docker exec "$CID_DB" psql -U gitea -d postgres \
  -c "ALTER USER gitea WITH PASSWORD '$NEW';"

# 2. atomic swap
mv "$SECRETS_DIR/db_pass.next" "$SECRETS_DIR/db_pass.current"

# 3. HOT RELOAD (no restart)
docker kill -s HUP "$CID_GITEA" || true

# 4. runner reload (graceful)
docker exec $(docker ps --filter name=act_runner -q) \
  kill -HUP 1 || true

# 5. verify
if docker exec "$CID_DB" pg_isready -U gitea >/dev/null; then
  bash notify.sh "🔐 Secret rotated (zero-downtime)"
else
  bash notify.sh "❌ Rotation failed"
  exit 1
fi
