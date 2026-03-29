# zt-gitea-v10 (Ultra Hardened)

Production-oriented Gitea deployment with zero-trust-inspired controls:

- tmpfs-based runtime secrets (`/run/zttato`)
- segmented Docker networks (`edge`, `app`, `db`)
- hardened reverse proxy (Caddy + TLS 1.3)
- reduced privileges (`no-new-privileges`, `cap_drop`, read-only fs)
- nftables host baseline
- runtime auditing and OS cleanup helpers

## Files

- `install-v10.sh` — full installer/provisioner for stack and firewall
- `scripts/audit-runtime.sh` — operational + security audit script
- `scripts/clean-os.sh` — cleanup script for Docker/cache/firewall reset

## Quick Start

```bash
cd zt-gitea-v10
chmod +x install-v10.sh scripts/*.sh
./install-v10.sh gitea.example.com
```

## Optional env vars

- `BASE_DIR` (default: `$HOME/zttato-v10`)
- `EMAIL` (default: `admin@<DOMAIN>`)
- `FORCE=true` to overwrite existing install dir

## Post-install checks

```bash
./scripts/audit-runtime.sh
```

## Security Notes

- This stack hardens host and container controls, but **is not a complete enterprise zero-trust mesh**.
- For higher assurance, add workload identity (SPIFFE/SPIRE), secret rotation via Vault, and per-service mTLS.
- Keep Gitea runner workloads isolated on separate worker hosts/VMs.
