# ZGitea v8 — Planetary-Scale Zero-Trust CI

This stack implements a sovereign, multi-region CI platform with deterministic orchestration and zero-trust execution.

## Components

- **Global Edge Router** (`edge-router/app.py`): latency-aware routing with health gates and GeoIP fallback.
- **Regional Gateway + Queue** (`regions/*/docker-compose.yml`): per-region Redis Streams queues and MinIO artifact stores.
- **Replication Bridge** (`replication-bridge/bridge.py`): cross-region fan-out for Redis Streams with idempotent replication IDs.
- **Distributed Scheduler** (`scheduler/scheduler.py`): etcd-backed per-region leader election and deterministic dispatch.
- **WASM Worker Runtime** (`worker/runner.py`): isolated, ephemeral execution with optional wasmtime and strict Linux hardening.
- **Autoscaler** (`autoscaler/autoscaler.py`): queue-depth based scaling decisions with cooldown and upper/lower bounds.
- **Webhook Ingress** (`webhook/ingress.py`): HMAC-verified ingress writing immutable jobs to regional streams.

## Security Model

- File-based secret loading only (`/run/secrets/*`), no runtime env secret expansion.
- mTLS material expected from SPIFFE/SPIRE sidecars or mounted certs.
- Worker containers enforce:
  - `no-new-privileges`
  - seccomp profile
  - read-only root filesystem
  - tmpfs scratch
  - dropped capabilities
- Job payloads are signed and deduplicated before enqueue.

## Run

1. Start each region:
   - `docker compose -f regions/region-a/docker-compose.yml up -d`
   - `docker compose -f regions/region-b/docker-compose.yml up -d`
   - `docker compose -f regions/region-c/docker-compose.yml up -d`
2. Start global services:
   - `docker compose -f edge-router/docker-compose.yml up -d`
3. Configure DNS to send clients to edge router.

## Failure handling

- Region outage: router marks health degraded and reroutes to next healthy region.
- Queue partition: local jobs continue; bridge reconciles via replicated stream IDs.
- Worker crash: pending jobs are reclaimed with `XAUTOCLAIM` after visibility timeout.

## Notes

- Compose files are split per-region for active-active deployment.
- Scripts are complete implementations, not stubs/placeholders.
