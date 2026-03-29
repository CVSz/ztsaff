#!/usr/bin/env bash
set -Eeuo pipefail

say() {
  printf '\n===== %s =====\n' "$1"
}

say "SYSTEM"
echo "[CPU]"
nproc || true
lscpu | grep -E 'Model name|CPU\(s\)|Thread|MHz' || true
echo "[MEMORY]"
free -h || true
echo "[DISK]"
df -hT || true
echo "[LOAD]"
uptime || true

say "DOCKER"
docker version --format '{{.Server.Version}}' || echo "Docker daemon unavailable"
docker info | grep -E 'Cgroup|Storage|Driver' || true

say "CONTAINERS"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Ports}}' || true

say "RESOURCE USAGE"
docker stats --no-stream || true

say "NETWORK"
docker network ls || true
ip -brief addr || true

say "SECURITY SETTINGS"
for c in $(docker ps -q); do
  echo "--- $c capabilities ---"
  docker inspect "$c" --format '{{json .HostConfig.CapDrop}} {{json .HostConfig.CapAdd}}'
  echo "--- $c seccomp ---"
  docker inspect "$c" --format '{{json .HostConfig.SecurityOpt}}'
done

say "GITEA HEALTH"
curl -sk https://localhost/api/healthz || echo "health endpoint failed"

say "POSTGRES READINESS"
pg_container="$(docker ps --filter name=zt-postgres --format '{{.ID}}' | head -n1 || true)"
if [[ -n "$pg_container" ]]; then
  docker exec "$pg_container" pg_isready -U gitea -d gitea || true
else
  echo "zt-postgres container not found"
fi

say "OPEN PORTS"
ss -tulpen || true

say "FIREWALL"
sudo nft list ruleset || echo "nft unavailable"

say "TMPFS SECRETS"
mount | grep zttato || echo "tmpfs /run/zttato not mounted"
ls -lah /run/zttato 2>/dev/null || true
