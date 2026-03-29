#!/usr/bin/env bash
set -Eeuo pipefail

echo "===== SYSTEM ====="
echo "[CPU]"
nproc
lscpu | grep -E 'Model name|CPU\(s\)|Thread|MHz'

echo "[MEMORY]"
free -h

echo "[DISK]"
df -hT

echo "[LOAD]"
uptime

echo
echo "===== DOCKER ====="
docker version --format '{{.Server.Version}}' || echo "Docker not running"
docker info | grep -E 'Cgroup|Storage|Driver'

echo
echo "===== CONTAINERS ====="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RunningFor}}\t{{.Ports}}"

echo
echo "===== RESOURCE USAGE ====="
docker stats --no-stream

echo
echo "===== NETWORK ====="
docker network ls
ip -brief addr

echo
echo "===== SECURITY ====="
echo "[Capabilities]"
for c in $(docker ps -q); do
  echo "--- $c ---"
  docker inspect "$c" | grep -i cap
done

echo
echo "[Seccomp]"
for c in $(docker ps -q); do
  echo "--- $c ---"
  docker inspect "$c" | grep -i seccomp
done

echo
echo "===== GITEA HEALTH ====="
curl -sk https://localhost/api/healthz || echo "Health endpoint failed"

echo
echo "===== POSTGRES ====="
docker exec -it $(docker ps --filter name=postgres -q) pg_isready -U gitea || true

echo
echo "===== OPEN PORTS ====="
ss -tulpen

echo
echo "===== FIREWALL ====="
sudo nft list ruleset || echo "No nft rules"

echo
echo "===== TMPFS SECRETS ====="
mount | grep zttato || echo "No tmpfs secrets mounted"
ls -lah /run/zttato 2>/dev/null || true
