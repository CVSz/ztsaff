#!/usr/bin/env bash
set -Eeuo pipefail

# block all outgoing traffic from runner network
iptables -I DOCKER-USER -i br-$(docker network inspect zgitea-installer_runner_net -f '{{.Id}}' | cut -c1-12) -j DROP || true
