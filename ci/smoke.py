#!/usr/bin/env python3
"""Run both password branches of a newly linked GCC or Pascal example."""
from pathlib import Path
import subprocess
import sys

exe = Path(sys.argv[1]).resolve()
for password, expected in [('13', 'Correct password'), ('12', 'Incorrect password')]:
    result = subprocess.run([str(exe)], input=password + '\n', text=True,
                            capture_output=True, cwd=exe.parent, timeout=15, check=True)
    if expected not in result.stdout:
        raise SystemExit(f'{exe}: expected {expected!r}, got {result.stdout!r} {result.stderr!r}')
    print(f'PASS: {exe.name}, input {password}: {expected}')
