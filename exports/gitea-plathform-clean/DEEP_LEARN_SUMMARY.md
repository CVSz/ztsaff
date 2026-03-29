# Deep learn summary: `exports/gitea-plathform`

This document summarizes the merged, cleaned platform export.

## What was merged

- Multiple historical revisions with suffixes like `__2`, `__3`, ... were consolidated into canonical filenames.
- Latest revision policy used:
  - `foo.sh` + `foo__2.sh` + `foo__3.sh` ⇒ keep `foo__3.sh` as `foo.sh`
  - same logic for `docker-compose` and `zgitea-installer` families.
- The cleaned output is written to `exports/gitea-plathform-clean/`.

## Key platform components discovered

- **Bootstrap & install:** `install-v10.sh`, `zgitea-installer.sh`, `install-docker-clean.sh`, `clean-os.sh`.
- **Security hardening:** `harden.sh`, `audit-runtime.sh`, `fix-runtime.sh`, `fix-gvisor.sh`, `runner-firewall.sh`.
- **Operations:** `backup.sh`, `rotate-secret.sh`, blue/green deploy scripts, health checks.
- **Ephemeral runner stack:** v5/v6/v7 compose files with worker/webhook/autoscaler scripts.
- **Global/multi-region:** edge router + region compose + replication/failover scripts.

## Merge output index

- Full per-file merge decisions are documented in `MERGE_REPORT.md`.
- Total canonical files after cleanup: **64**.

## Notes

- This cleanup is non-destructive to the original export; source remains in `exports/gitea-plathform/`.
- `MERGE_REPORT.md` can be used to trace any canonical file back to all original variants.
