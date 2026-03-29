#!/usr/bin/env bash
set -Eeuo pipefail

echo "[1] STOP ALL CONTAINERS"
docker stop $(docker ps -aq) 2>/dev/null || true

echo "[2] REMOVE ALL CONTAINERS"
docker rm -f $(docker ps -aq) 2>/dev/null || true

echo "[3] REMOVE ALL IMAGES"
docker rmi -f $(docker images -aq) 2>/dev/null || true

echo "[4] REMOVE VOLUMES"
docker volume rm $(docker volume ls -q) 2>/dev/null || true

echo "[5] REMOVE NETWORKS"
docker network rm $(docker network ls -q | grep -v bridge | grep -v host | grep -v none) 2>/dev/null || true

echo "[6] PURGE DOCKER (BROKEN INSTALL)"
sudo apt-get purge -y docker docker-engine docker.io containerd runc || true
sudo rm -rf /var/lib/docker /var/lib/containerd

echo "[7] CLEAN CLI PLUGINS (CORRUPTED)"
sudo rm -rf /usr/local/lib/docker
sudo rm -rf ~/.docker

echo "[8] DISK CLEAN"
sudo apt-get autoremove -y
sudo apt-get autoclean -y

echo "[9] K3D CLEAN"
k3d cluster delete --all || true

echo "[10] RESET IPTABLES/NFT"
sudo iptables -F || true
sudo nft flush ruleset || true

echo "[11] REMOVE UNUSED FILESYSTEM PRESSURE"
sudo rm -rf /tmp/*
sudo journalctl --vacuum-time=1d || true

echo "[✓] CLEAN COMPLETE"
