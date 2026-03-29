#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
python3 -m pip install --upgrade pip
make install

echo "Bootstrap complete. Run 'make up' to launch local stack."
