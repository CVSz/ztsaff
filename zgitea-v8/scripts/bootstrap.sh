#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for region in region-a region-b region-c; do
  docker compose -f "${ROOT_DIR}/regions/${region}/docker-compose.yml" up -d
  echo "Started ${region}"
done

docker compose -f "${ROOT_DIR}/edge-router/docker-compose.yml" up -d

echo "ZGitea v8 control plane started"
