#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${HOME}/zttato-local"
BACKUP_DIR="${BASE_DIR}/backup"
mkdir -p "$BACKUP_DIR"

############################################
# 1. BACKUP SCRIPT (POSTGRES + GITEA DATA)
############################################
cat > "${BASE_DIR}/backup.sh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

TS=$(date +%Y%m%d-%H%M%S)
OUT="${HOME}/zttato-local/backup/$TS"
mkdir -p "$OUT"

echo "[*] Dump Postgres"
docker exec $(docker ps --filter name=postgres -q) \
  pg_dump -U gitea gitea > "$OUT/db.sql"

echo "[*] Snapshot Gitea"
tar -czf "$OUT/gitea.tar.gz" -C ~/zttato-local gitea-data 2>/dev/null || true

echo "[*] Cleanup old (keep 7)"
ls -dt ${HOME}/zttato-local/backup/* | tail -n +8 | xargs -r rm -rf

echo "[OK] backup complete $TS"
EOF

chmod +x "${BASE_DIR}/backup.sh"

############################################
# 2. AUTO CRON BACKUP (EVERY 6 HOURS)
############################################
(crontab -l 2>/dev/null; echo "0 */6 * * * ${BASE_DIR}/backup.sh") | crontab -

############################################
# 3. AUTO-HEAL WATCHDOG
############################################
cat > "${BASE_DIR}/autoheal.sh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

for c in $(docker ps --format '{{.Names}}'); do
  STATUS=$(docker inspect --format '{{.State.Health.Status}}' "$c" 2>/dev/null || echo "none")

  if [[ "$STATUS" == "unhealthy" ]]; then
    echo "[HEAL] restarting $c"
    docker restart "$c"
  fi
done
EOF

chmod +x "${BASE_DIR}/autoheal.sh"

(crontab -l 2>/dev/null; echo "*/2 * * * * ${BASE_DIR}/autoheal.sh") | crontab -

############################################
# 4. CLOUDFLARE TUNNEL (ZERO COST)
############################################
cat > "${BASE_DIR}/cloudflare.sh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

docker run -d \
  --name cloudflare-tunnel \
  --restart unless-stopped \
  cloudflare/cloudflared:latest \
  tunnel --no-autoupdate run \
  --token YOUR_CLOUDFLARE_TOKEN
EOF

chmod +x "${BASE_DIR}/cloudflare.sh"

echo "[!] Replace YOUR_CLOUDFLARE_TOKEN before run cloudflare.sh"

############################################
# 5. SNAPSHOT (FAST LOCAL)
############################################
cat > "${BASE_DIR}/snapshot.sh" << 'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

SNAP_DIR="${HOME}/zttato-local/snapshots"
mkdir -p "$SNAP_DIR"

TS=$(date +%Y%m%d-%H%M%S)

tar -czf "$SNAP_DIR/snap-$TS.tar.gz" \
  -C "${HOME}/zttato-local" docker-compose.yml Caddyfile 2>/dev/null || true

ls -dt ${SNAP_DIR}/* | tail -n +6 | xargs -r rm -f

echo "[OK] snapshot $TS"
EOF

chmod +x "${BASE_DIR}/snapshot.sh"

(crontab -l 2>/dev/null; echo "0 3 * * * ${BASE_DIR}/snapshot.sh") | crontab -

############################################
# DONE
############################################
echo "[OK] addon installed"
echo "- backup: every 6h"
echo "- autoheal: every 2min"
echo "- snapshot: daily"
echo "- cloudflare: manual run required"
