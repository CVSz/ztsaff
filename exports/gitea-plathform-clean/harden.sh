#!/usr/bin/env bash
set -Eeuo pipefail

chmod +x *.sh
sed -i 's/\r$//' *.sh

# prevent world read
chmod 700 "$HOME/zgitea-installer"
