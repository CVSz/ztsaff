#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / 'ROOT_PROJECT_FULL_SOURCE_MERGED.md'

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

PROTECTED_FILES = {
    'ROOT_PROJECT_SOURCE_MERGED.md',
    'ROOT_PROJECT_FULL_SOURCE_MERGED.md',
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Deep-scan source files, merge into root artifact, optionally clean/delete merged files.'
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f'Path for merged output (default: {DEFAULT_OUTPUT})',
    )
    parser.add_argument(
        '--delete-after-merge',
        action='store_true',
        help='Delete source files after successful merge output write.',
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be merged/deleted without writing or deleting files.',
    )
    return parser.parse_args()


def should_skip(path: Path) -> bool:
    if any(part in SKIP_DIRS for part in path.parts):
        return True
    if path.name in PROTECTED_FILES:
        return True
    return False


def collect_source_files(root: Path, output: Path) -> list[Path]:
    files: list[Path] = []
    out_abs = output.resolve()
    for path in root.rglob('*'):
        if not path.is_file() or should_skip(path):
            continue
        if path.resolve() == out_abs:
            continue
        if path.suffix.lower() in SOURCE_EXTS:
            files.append(path)
    return sorted(files, key=lambda p: str(p.relative_to(root)))


def build_merged_document(root: Path, files: list[Path]) -> str:
    lines: list[str] = [
        '# Root Project Full Source (Deep Merged)',
        '',
        f'- Root: `{root}`',
        f'- Source files merged: **{len(files)}**',
        '',
        '## File Index',
        '',
    ]

    for index, path in enumerate(files, start=1):
        lines.append(f'{index}. `{path.relative_to(root)}`')

    lines += ['', '## Merged Source', '']

    for path in files:
        rel = path.relative_to(root)
        body = path.read_text(encoding='utf-8', errors='replace').rstrip()
        lines.extend([
            f'### `{rel}`',
            '',
            '```text',
            body,
            '```',
            '',
        ])

    return '\n'.join(lines).rstrip() + '\n'


def delete_files(files: list[Path]) -> int:
    deleted = 0
    for path in files:
        if path.exists() and path.is_file():
            path.unlink()
            deleted += 1
    return deleted


def main() -> None:
    args = parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    files = collect_source_files(ROOT, output)

    if args.dry_run:
        print(f'[DRY RUN] Files selected for merge: {len(files)}')
        if args.delete_after_merge:
            print(f'[DRY RUN] Files that would be deleted: {len(files)}')
        return

    merged = build_merged_document(ROOT, files)
    output.write_text(merged, encoding='utf-8')
    print(f'Wrote merged source artifact: {output} ({len(files)} files)')

    if args.delete_after_merge:
        deleted = delete_files(files)
        print(f'Deleted source files after merge: {deleted}')


if __name__ == '__main__':
    main()
