#!/usr/bin/env python3
"""Verify the archive manifest, SDK links, and the absence of shipped executables."""
import argparse
import hashlib
import json
import os
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, default=REPO)
parser.add_argument('--build-tree', action='store_true', help='Accept materialized SDK links and newly built executables')
args = parser.parse_args()
manifest = json.loads((REPO / 'extraction-manifest.json').read_text())
errors = []
for name, record in manifest['files'].items():
    path = args.root / name
    if not path.is_file():
        errors.append(f'Missing file: {name}')
        continue
    if hashlib.sha256(path.read_bytes()).hexdigest() != record['sha256']:
        errors.append(f'Changed original bytes: {name}')
    if not args.build_tree:
        if 'link' in record:
            if not path.is_symlink() or os.readlink(path).replace('\\', '/') != record['link']:
                errors.append(f'Wrong SDK symlink: {name}')
        elif path.is_symlink():
            errors.append(f'Unexpected symlink: {name}')
if not args.build_tree:
    expected = set(manifest['files'])
    actual = {p.relative_to(args.root).as_posix() for r in ('Examples', 'Include', 'Lib')
              for p in (args.root / r).rglob('*') if p.is_file() or p.is_symlink()}
    for name in sorted(actual - expected):
        errors.append(f'Unexpected file: {name}')
    for name in manifest['removed']:
        if os.path.lexists(args.root / name):
            errors.append(f'Shipped executable still present: {name}')
if errors:
    raise SystemExit('\n'.join(errors))
print(f'PASS: {len(manifest["files"])} original file/link hashes; SDK and sources unchanged.')
