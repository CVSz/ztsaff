#!/usr/bin/env bash
set -Eeuo pipefail

# disable legacy features
sudo sysctl -w net.ipv4.ip_forward=0
sudo sysctl -w kernel.unprivileged_userns_clone=0

# restrict docker socket
sudo chmod 660 /var/run/docker.sock

# enable cgroup v2 enforcement check
docker info | grep "Cgroup Version"
