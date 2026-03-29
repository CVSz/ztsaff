#!/usr/bin/env bash
set -Eeuo pipefail

curl -sf https://localhost/api/healthz | grep ok
