#!/usr/bin/env bash
set -Eeuo pipefail

PORT=8088
SECRET="$(cat /run/zgitea-installer/webhook_secret)"

while true; do
  REQ=$(nc -l -p $PORT)
  BODY=$(echo "$REQ" | sed -n '/^\r$/,$p' | tail -n +2)
  SIG=$(echo "$REQ" | grep -i 'X-Hub-Signature-256:' | awk '{print $2}' | tr -d '\r')

  EXPECTED="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')"

  [[ "$SIG" != "$EXPECTED" ]] && continue

  JOB_ID=$(echo "$BODY" | jq -r '.job.id // empty')

  [[ -n "$JOB_ID" ]] && redis-cli -h redis XADD jobs * job_id "$JOB_ID" >/dev/null
done
