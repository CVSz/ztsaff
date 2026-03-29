#!/usr/bin/env bash
set -Eeuo pipefail

ARCH=$(uname -m)

# download full bundle
curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/runsc \
  -o /usr/local/bin/runsc

curl -fsSL https://storage.googleapis.com/gvisor/releases/release/latest/containerd-shim-runsc-v1 \
  -o /usr/local/bin/containerd-shim-runsc-v1

chmod +x /usr/local/bin/runsc
chmod +x /usr/local/bin/containerd-shim-runsc-v1

# verify
runsc --version || true

echo "[OK] gVisor FULL installed"
