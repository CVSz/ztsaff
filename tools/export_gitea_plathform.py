#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

SRC = Path('Gitea-plathform.md')
OUT = Path('exports/gitea-plathform')

raw = SRC.read_text(encoding='utf-8')
pattern = re.compile(r"```\n# path: ([^\n]+)\n(.*?)```", re.S)

OUT.mkdir(parents=True, exist_ok=True)
manifest = []
seen: dict[str, int] = {}

for m in pattern.finditer(raw):
    raw_label = m.group(1).strip()
    body = m.group(2)

    # Normalize noisy labels like "foo.sh (PATCH)" or comments after spaces.
    label = raw_label
    if ' (' in label:
        label = label.split(' (', 1)[0].strip()
    if ' ' in label and not label.endswith('.yml') and not label.endswith('.sh') and not label.endswith('.json') and not label.endswith('.md') and not label.endswith('.txt'):
        label = label.split(' ', 1)[0].strip()

    # keep exports self-contained and safe
    label = label.lstrip('/').replace('..', '__')
    if not label:
        continue

    idx = seen.get(label, 0) + 1
    seen[label] = idx
    path = Path(label)
    if idx > 1:
        stem = path.stem
        suffix = path.suffix
        path = path.with_name(f"{stem}__{idx}{suffix}")

    target = OUT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(body.rstrip() + "\n", encoding='utf-8')
    manifest.append((raw_label, str(path)))

manifest_path = OUT / 'MANIFEST.md'
lines = [
    '# Export manifest from `Gitea-plathform.md`',
    '',
    f'- Source: `{SRC}`',
    f'- Export root: `{OUT}`',
    f'- Blocks exported: **{len(manifest)}**',
    '',
    '| Original `# path:` label | Exported file |',
    '|---|---|',
]
for src_label, file_path in manifest:
    lines.append(f'| `{src_label}` | `{file_path}` |')
manifest_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')

print(f'Exported {len(manifest)} code blocks to {OUT}')
