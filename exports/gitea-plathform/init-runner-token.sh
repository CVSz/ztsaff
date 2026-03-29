
if [[ ! -f "$SECRETS_DIR/runner_token" ]]; then
  echo "[INFO] Waiting for Gitea API..."

  until curl -sf http://localhost:3000/api/healthz >/dev/null; do
    sleep 2
  done

  TOKEN=$(docker exec $(docker ps --filter name=gitea -q) \
    gitea actions generate-runner-token)

  echo "$TOKEN" > "$SECRETS_DIR/runner_token"
  chmod 600 "$SECRETS_DIR/runner_token"
fi
