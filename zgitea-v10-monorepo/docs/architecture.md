# ZGitea v10 Architecture Mapping

This document maps the design prompt to implementation stubs in this monorepo.

- Edge Layer → `apps/edge-router`
- Control Plane → `apps/control-plane`
- Intelligence Layer → `apps/ai-scheduler`
- Execution Layer → `apps/worker`
- Deploy topology → `deploy/docker-compose.yml`
- IaC baseline → `infra/terraform`

## Security hooks to implement next

1. SPIFFE/SPIRE workload identity integration
2. End-to-end mTLS and cert rotation
3. Artifact encryption with KMS envelope keys
4. Strict network policy and sandbox enforcement
