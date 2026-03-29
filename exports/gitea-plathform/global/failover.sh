#!/usr/bin/env bash
set -Eeuo pipefail

PRIMARY="region-a"
SECONDARY="region-b"

if ! curl -sf http://$PRIMARY:8080/health >/dev/null; then
  echo "[FAILOVER] switching to $SECONDARY"
  echo "$SECONDARY" > /tmp/active-region
else
  echo "$PRIMARY" > /tmp/active-region
fi
