#!/usr/bin/env bash
set -Eeuo pipefail

REGIONS=("region-a" "region-b")
declare -A URLS=(
  ["region-a"]="http://region-a:8080/health"
  ["region-b"]="http://region-b:8080/health"
)

best=""
best_latency=999999

for r in "${REGIONS[@]}"; do
  t=$(curl -o /dev/null -s -w "%{time_total}" "${URLS[$r]}" || echo 999)
  t_ms=$(echo "$t * 1000" | bc | cut -d. -f1)

  if (( t_ms < best_latency )); then
    best_latency=$t_ms
    best=$r
  fi
done

echo "$best"
