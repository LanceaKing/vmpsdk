#!/usr/bin/env python3
"""Materialize a fresh build tree; never build inside the imported archive."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
work = root / '.build/work'
if work.exists():
    raise SystemExit(f'Refusing to overwrite {work}')
work.mkdir(parents=True)
for name in ('Examples', 'Include', 'Lib'):
    shutil.copytree(root / name, work / name, symlinks=False)
(root / '.build/artifacts').mkdir(parents=True)
print(f'Build tree: {work}')
