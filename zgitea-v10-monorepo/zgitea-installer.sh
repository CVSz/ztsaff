#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "[ZGitea v10] Bootstrapping monorepo..."
bash scripts/bootstrap.sh

echo "[ZGitea v10] Starting local services..."
make up

echo "[ZGitea v10] Done. Edge router available at http://localhost:8080"
