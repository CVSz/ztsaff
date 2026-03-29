# gitea-plathform merged & cleaned export

- Source: `exports/gitea-plathform`
- Output: `exports/gitea-plathform-clean`
- Unique canonical files: **64**

## Merge decisions

| Canonical file | Selected source | Variants |
|---|---|---|
| `.env.example` | `.env.example` | `.env.example` |
| `.gitea/workflows/ci.yml` | `.gitea/workflows/ci.yml` | `.gitea/workflows/ci.yml` |
| `.github/workflows/ci.yml` | `.github/workflows/ci.yml` | `.github/workflows/ci.yml` |
| `.github/workflows/deploy.yml` | `.github/workflows/deploy__2.yml` | `.github/workflows/deploy.yml`<br>`.github/workflows/deploy__2.yml` |
| `Caddyfile` | `Caddyfile` | `Caddyfile` |
| `Makefile` | `Makefile` | `Makefile` |
| `addons/ephemeral-runner.sh` | `addons/ephemeral-runner.sh` | `addons/ephemeral-runner.sh` |
| `addons/ephemeral-v4.sh` | `addons/ephemeral-v4.sh` | `addons/ephemeral-v4.sh` |
| `ai-engine.sh` | `ai-engine__2.sh` | `ai-engine.sh`<br>`ai-engine__2.sh` |
| `audit-runtime.sh` | `audit-runtime.sh` | `audit-runtime.sh` |
| `backup.sh` | `backup__2.sh` | `backup.sh`<br>`backup__2.sh` |
| `clean-os.sh` | `clean-os.sh` | `clean-os.sh` |
| `docker-compose.bluegreen.yml` | `docker-compose.bluegreen.yml` | `docker-compose.bluegreen.yml` |
| `docker-compose.ephemeral-v5.yml` | `docker-compose.ephemeral-v5.yml` | `docker-compose.ephemeral-v5.yml` |
| `docker-compose.ephemeral-v6.yml` | `docker-compose.ephemeral-v6.yml` | `docker-compose.ephemeral-v6.yml` |
| `docker-compose.ephemeral-v7.yml` | `docker-compose.ephemeral-v7.yml` | `docker-compose.ephemeral-v7.yml` |
| `docker-compose.yml` | `docker-compose__4.yml` | `docker-compose.yml`<br>`docker-compose__2.yml`<br>`docker-compose__3.yml`<br>`docker-compose__4.yml` |
| `edge/router.sh` | `edge/router.sh` | `edge/router.sh` |
| `ephemeral-v5/autoscaler-stream.sh` | `ephemeral-v5/autoscaler-stream.sh` | `ephemeral-v5/autoscaler-stream.sh` |
| `ephemeral-v5/spawn-runner.sh` | `ephemeral-v5/spawn-runner.sh` | `ephemeral-v5/spawn-runner.sh` |
| `ephemeral-v5/webhook-stream.sh` | `ephemeral-v5/webhook-stream.sh` | `ephemeral-v5/webhook-stream.sh` |
| `ephemeral-v5/worker-stream.sh` | `ephemeral-v5/worker-stream.sh` | `ephemeral-v5/worker-stream.sh` |
| `ephemeral-v6/cache-proxy.sh` | `ephemeral-v6/cache-proxy.sh` | `ephemeral-v6/cache-proxy.sh` |
| `ephemeral-v6/spawn-runner-wasm.sh` | `ephemeral-v6/spawn-runner-wasm.sh` | `ephemeral-v6/spawn-runner-wasm.sh` |
| `ephemeral-v6/spire-agent.conf` | `ephemeral-v6/spire-agent.conf` | `ephemeral-v6/spire-agent.conf` |
| `ephemeral-v6/spire-server.conf` | `ephemeral-v6/spire-server.conf` | `ephemeral-v6/spire-server.conf` |
| `ephemeral-v6/webhook-stream.sh` | `ephemeral-v6/webhook-stream.sh` | `ephemeral-v6/webhook-stream.sh` |
| `ephemeral-v6/worker-stream.sh` | `ephemeral-v6/worker-stream.sh` | `ephemeral-v6/worker-stream.sh` |
| `ephemeral-v7/autoscaler.sh` | `ephemeral-v7/autoscaler.sh` | `ephemeral-v7/autoscaler.sh` |
| `ephemeral-v7/etcd.yaml` | `ephemeral-v7/etcd.yaml` | `ephemeral-v7/etcd.yaml` |
| `ephemeral-v7/scheduler.sh` | `ephemeral-v7/scheduler.sh` | `ephemeral-v7/scheduler.sh` |
| `ephemeral-v7/webhook.sh` | `ephemeral-v7/webhook.sh` | `ephemeral-v7/webhook.sh` |
| `ephemeral-v7/worker.sh` | `ephemeral-v7/worker.sh` | `ephemeral-v7/worker.sh` |
| `etc/docker/daemon.json` | `etc/docker/daemon.json` | `etc/docker/daemon.json` |
| `fix-cron-safe.sh` | `fix-cron-safe.sh` | `fix-cron-safe.sh` |
| `fix-gvisor.sh` | `fix-gvisor.sh` | `fix-gvisor.sh` |
| `fix-runtime.sh` | `fix-runtime.sh` | `fix-runtime.sh` |
| `global/failover.sh` | `global/failover.sh` | `global/failover.sh` |
| `global/replication.sh` | `global/replication.sh` | `global/replication.sh` |
| `harden.sh` | `harden__2.sh` | `harden.sh`<br>`harden__2.sh` |
| `init-runner-token.sh` | `init-runner-token.sh` | `init-runner-token.sh` |
| `install-docker-clean.sh` | `install-docker-clean.sh` | `install-docker-clean.sh` |
| `install-v10.sh` | `install-v10.sh` | `install-v10.sh` |
| `regions/region-a/docker-compose.yml` | `regions/region-a/docker-compose.yml` | `regions/region-a/docker-compose.yml` |
| `rotate-secret.sh` | `rotate-secret.sh` | `rotate-secret.sh` |
| `runner-firewall.sh` | `runner-firewall.sh` | `runner-firewall.sh` |
| `scripts/autoheal.sh` | `scripts/autoheal.sh` | `scripts/autoheal.sh` |
| `scripts/backup.sh` | `scripts/backup.sh` | `scripts/backup.sh` |
| `scripts/cloudflare.sh` | `scripts/cloudflare.sh` | `scripts/cloudflare.sh` |
| `scripts/deploy-bluegreen.sh` | `scripts/deploy-bluegreen.sh` | `scripts/deploy-bluegreen.sh` |
| `scripts/firewall.sh` | `scripts/firewall.sh` | `scripts/firewall.sh` |
| `scripts/health.sh` | `scripts/health.sh` | `scripts/health.sh` |
| `scripts/install.sh` | `scripts/install.sh` | `scripts/install.sh` |
| `scripts/rollback.sh` | `scripts/rollback.sh` | `scripts/rollback.sh` |
| `scripts/secrets.sh` | `scripts/secrets.sh` | `scripts/secrets.sh` |
| `scripts/snapshot.sh` | `scripts/snapshot.sh` | `scripts/snapshot.sh` |
| `zgitea-installer.sh` | `zgitea-installer__15.sh` | `zgitea-installer.sh`<br>`zgitea-installer__2.sh`<br>`zgitea-installer__3.sh`<br>`zgitea-installer__4.sh`<br>`zgitea-installer__5.sh`<br>`zgitea-installer__6.sh`<br>`zgitea-installer__7.sh`<br>`zgitea-installer__8.sh`<br>`zgitea-installer__9.sh`<br>`zgitea-installer__10.sh`<br>`zgitea-installer__11.sh`<br>`zgitea-installer__12.sh`<br>`zgitea-installer__13.sh`<br>`zgitea-installer__14.sh`<br>`zgitea-installer__15.sh` |
| `zgitea-v8` | `zgitea-v8` | `zgitea-v8` |
| `zttato-ultimate.sh` | `zttato-ultimate.sh` | `zttato-ultimate.sh` |
| `zttato-v10-addon.sh` | `zttato-v10-addon.sh` | `zttato-v10-addon.sh` |
| `zttato-v10-auto.sh` | `zttato-v10-auto.sh` | `zttato-v10-auto.sh` |
| `zttato-v10-full.sh` | `zttato-v10-full.sh` | `zttato-v10-full.sh` |
| `zttato-v10-localhost.sh` | `zttato-v10-localhost.sh` | `zttato-v10-localhost.sh` |
| `zttato-v11-meta.sh` | `zttato-v11-meta.sh` | `zttato-v11-meta.sh` |
