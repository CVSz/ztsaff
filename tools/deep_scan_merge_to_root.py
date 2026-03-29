#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'ROOT_PROJECT_SOURCE_MERGED.md'

SOURCE_EXTS = {
    '.py', '.sh', '.tf', '.md', '.yml', '.yaml', '.json', '.toml', '.ini', '.conf',
    '.js', '.ts', '.tsx', '.jsx', '.go', '.rs', '.java', '.rb', '.php', '.sql', '.txt'
}

SKIP_DIRS = {
    '.git',
    'node_modules',
    '.venv',
    'venv',
    '__pycache__',
    '.mypy_cache',
    '.pytest_cache',
    'dist',
    'build',
}

SKIP_FILES = {
    'ROOT_PROJECT_SOURCE_MERGED.md',
}


def should_skip(path: Path) -> bool:
    if any(part in SKIP_DIRS for part in path.parts):
        return True
    if path.name in SKIP_FILES:
        return True
    return False


def iter_source_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for p in root.rglob('*'):
        if not p.is_file() or should_skip(p):
            continue
        if p.suffix.lower() in SOURCE_EXTS:
            files.append(p)
    return sorted(files, key=lambda x: str(x.relative_to(root)))


def main() -> None:
    files = iter_source_files(ROOT)

    lines: list[str] = [
        '# Root Project Deep Scan + Merged Source Index',
        '',
        f'- Root: `{ROOT}`',
        f'- Source-like files included: **{len(files)}**',
        '',
        '## File Index',
        '',
    ]

    for i, p in enumerate(files, start=1):
        rel = p.relative_to(ROOT)
        lines.append(f'{i}. `{rel}`')

    lines += ['', '## Merged Source Snapshot', '']

    for p in files:
        rel = p.relative_to(ROOT)
        content = p.read_text(encoding='utf-8', errors='replace').rstrip()
        lines += [
            f'### `{rel}`',
            '',
            '```text',
            content,
            '```',
            '',
        ]

    OUTPUT.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Wrote merged snapshot with {len(files)} files to {OUTPUT}')


if __name__ == '__main__':
    main()
