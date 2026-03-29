#!/usr/bin/env bash
set -Eeuo pipefail

SECRETS_DIR="/run/zttato-secrets"
sudo mkdir -p "$SECRETS_DIR"
sudo mount -t tmpfs -o size=1M tmpfs "$SECRETS_DIR"

openssl rand -hex 32 | sudo tee $SECRETS_DIR/db_pass >/dev/null
openssl rand -hex 32 | sudo tee $SECRETS_DIR/internal_token >/dev/null

sudo chmod 600 $SECRETS_DIR/*
