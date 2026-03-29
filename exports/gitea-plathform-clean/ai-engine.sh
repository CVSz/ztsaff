#!/usr/bin/env bash
set -Eeuo pipefail

LOCK="/tmp/zgitea-ai.lock"
exec 9>"$LOCK"
flock -n 9 || exit 0

STATE="/tmp/zgitea-ai-state"
CPU=$(top -bn1 | awk '/Cpu/ {print 100 - $8}')

CRITICAL="postgres|gitea|prometheus|grafana"

if (( ${CPU%.*} > 85 )); then
  TARGET=$(docker stats --no-stream \
    --format "{{.Name}} {{.CPUPerc}}" \
    | grep -vE "$CRITICAL" \
    | sort -k2 -nr \
    | head -1 \
    | awk '{print $1}')

  if [[ -n "$TARGET" ]]; then
    NOW=$(date +%s)
    LAST=$(grep "$TARGET" "$STATE" 2>/dev/null | awk '{print $2}' || echo 0)

    if (( NOW - LAST > 120 )); then
      docker restart "$TARGET"

      sed -i "/$TARGET/d" "$STATE" 2>/dev/null || true
      echo "$TARGET $NOW" >> "$STATE"

      bash rate.sh "🤖 AI-SRE restart: $TARGET"
    fi
  fi
fi
