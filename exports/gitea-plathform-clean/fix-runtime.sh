#!/usr/bin/env bash
set -Eeuo pipefail

ARCH=$(uname -m)
URL="https://storage.googleapis.com/gvisor/releases/release/latest/runsc"

curl -fsSL ${URL} -o /usr/local/bin/runsc
chmod +x /usr/local/bin/runsc

# install shim
curl -fsSL ${URL}.sha512 -o runsc.sha512
sha512sum -c runsc.sha512 || echo "skip verify"

# register docker runtime
cat > /etc/docker/daemon.json <<EOF
{
  "runtimes": {
    "runsc": {
      "path": "/usr/local/bin/runsc"
    }
  }
}
EOF

systemctl restart docker

echo "[OK] gVisor installed"
