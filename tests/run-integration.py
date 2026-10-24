#!/usr/bin/env python3
"""Run every standalone integration suite, including hyphenated filenames."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
suites = sorted(root.glob('test-*.py'))
if not suites:
    raise SystemExit('No integration suites found')
for suite in suites:
    print(f'== {suite.name} ==', flush=True)
    subprocess.run([sys.executable, str(suite)], check=True)
print(f'All {len(suites)} integration suites passed.')
