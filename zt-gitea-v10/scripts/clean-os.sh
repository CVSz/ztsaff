#!/usr/bin/env bash
set -Eeuo pipefail

log() { echo ">>> $*"; }

log "Stopping docker stack if present"
if [[ -f docker-compose.yml ]]; then
  docker compose down --remove-orphans || true
fi

log "Removing broken docker CLI plugin stubs"
for plugin_dir in "$HOME/.docker/cli-plugins" "/usr/local/lib/docker/cli-plugins"; do
  if [[ -d "$plugin_dir" ]]; then
    find "$plugin_dir" -maxdepth 1 -type l -delete || true
    find "$plugin_dir" -maxdepth 1 -type f ! -perm -111 -delete || true
  fi
done

log "Pruning unused docker resources"
docker system prune -af --volumes || true

log "Cleaning temp and cache"
rm -rf "$HOME/.cache"/* || true
sudo find /tmp -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true

log "Resetting nftables ruleset (optional baseline)"
sudo nft flush ruleset || true

log "Checking core service states"
systemctl is-active docker || true

log "Done"
