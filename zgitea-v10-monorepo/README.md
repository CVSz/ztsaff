# ZGitea v10 Monorepo

Sovereign, zero-trust, autonomous CI/CD platform scaffold generated from `prompt.md`.

## What this repository includes

- **Apps**
  - `apps/edge-router`: edge ingress and webhook validation stub
  - `apps/control-plane`: Raft/etcd-oriented scheduler coordination stub
  - `apps/worker`: ephemeral runner abstraction (WASM-first, container fallback)
  - `apps/ai-scheduler`: predictive scaling heuristics
- **Infrastructure as Code**
  - `infra/terraform`: starter Terraform stack + modules
- **Deployment**
  - `deploy/docker-compose.yml`: local dev topology
- **Automation**
  - `.github/workflows/ci.yml`: lint/test/build checks
  - `scripts/bootstrap.sh`: setup script

## Quick start

```bash
cd zgitea-v10-monorepo
bash scripts/bootstrap.sh
make up
```

## Production notes

- Replace placeholder Terraform values in `infra/terraform/terraform.tfvars.example`
- Configure SPIFFE/SPIRE, mTLS cert rotation, and MinIO/S3 KMS key management
- Add real etcd + Redis Streams + queue replication wiring
- Harden runtime with gVisor and seccomp profiles in your target environment
