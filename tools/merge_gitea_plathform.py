#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
from collections import defaultdict
from pathlib import Path

SRC = Path('exports/gitea-plathform')
OUT = Path('exports/gitea-plathform-clean')

SUFFIX_RE = re.compile(r'^(?P<stem>.+?)__(?P<rev>\d+)(?P<ext>\.[^.]+)?$')


def parse_variant(p: Path) -> tuple[str, int, str]:
    """Return canonical relative path, revision number, and source rel path."""
    rel = p.relative_to(SRC)
    name = rel.name
    m = SUFFIX_RE.match(name)
    if m:
        rev = int(m.group('rev'))
        ext = m.group('ext') or ''
        canonical_name = f"{m.group('stem')}{ext}"
    else:
        rev = 1
        canonical_name = name

    canonical_rel = rel.with_name(canonical_name)
    return str(canonical_rel), rev, str(rel)


def is_export_helper_file(p: Path) -> bool:
    return p.name in {'MANIFEST.md', 'tree.txt'}


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f'Missing source directory: {SRC}')

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    groups: dict[str, list[tuple[int, Path, str]]] = defaultdict(list)

    for path in SRC.rglob('*'):
        if not path.is_file() or is_export_helper_file(path):
            continue
        canonical, rev, rel = parse_variant(path)
        groups[canonical].append((rev, path, rel))

    merged = []
    for canonical, versions in sorted(groups.items()):
        versions.sort(key=lambda x: (x[0], x[2]))
        chosen_rev, chosen_path, chosen_rel = versions[-1]
        dest = OUT / canonical
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(chosen_path, dest)

        merged.append(
            {
                'canonical': canonical,
                'chosen': chosen_rel,
                'revision': chosen_rev,
                'variants': [v[2] for v in versions],
            }
        )

    report = [
        '# gitea-plathform merged & cleaned export',
        '',
        f'- Source: `{SRC}`',
        f'- Output: `{OUT}`',
        f'- Unique canonical files: **{len(merged)}**',
        '',
        '## Merge decisions',
        '',
        '| Canonical file | Selected source | Variants |',
        '|---|---|---|',
    ]

    for item in merged:
        variants = '<br>'.join(f'`{v}`' for v in item['variants'])
        report.append(f"| `{item['canonical']}` | `{item['chosen']}` | {variants} |")

    (OUT / 'MERGE_REPORT.md').write_text('\n'.join(report) + '\n', encoding='utf-8')

    summary = [
        '# Deep learn summary: `exports/gitea-plathform`',
        '',
        'This document summarizes the merged, cleaned platform export.',
        '',
        '## What was merged',
        '',
        '- Multiple historical revisions with suffixes like `__2`, `__3`, ... were consolidated into canonical filenames.',
        '- Latest revision policy used:',
        '  - `foo.sh` + `foo__2.sh` + `foo__3.sh` ⇒ keep `foo__3.sh` as `foo.sh`',
        '  - same logic for `docker-compose` and `zgitea-installer` families.',
        '- The cleaned output is written to `exports/gitea-plathform-clean/`.',
        '',
        '## Key platform components discovered',
        '',
        '- **Bootstrap & install:** `install-v10.sh`, `zgitea-installer.sh`, `install-docker-clean.sh`, `clean-os.sh`.',
        '- **Security hardening:** `harden.sh`, `audit-runtime.sh`, `fix-runtime.sh`, `fix-gvisor.sh`, `runner-firewall.sh`.',
        '- **Operations:** `backup.sh`, `rotate-secret.sh`, blue/green deploy scripts, health checks.',
        '- **Ephemeral runner stack:** v5/v6/v7 compose files with worker/webhook/autoscaler scripts.',
        '- **Global/multi-region:** edge router + region compose + replication/failover scripts.',
        '',
        '## Merge output index',
        '',
        '- Full per-file merge decisions are documented in `MERGE_REPORT.md`.',
        f'- Total canonical files after cleanup: **{len(merged)}**.',
        '',
        '## Notes',
        '',
        '- This cleanup is non-destructive to the original export; source remains in `exports/gitea-plathform/`.',
        '- `MERGE_REPORT.md` can be used to trace any canonical file back to all original variants.',
    ]

    (OUT / 'DEEP_LEARN_SUMMARY.md').write_text('\n'.join(summary) + '\n', encoding='utf-8')
    print(f'Wrote {len(merged)} files to {OUT}')


if __name__ == '__main__':
    main()
