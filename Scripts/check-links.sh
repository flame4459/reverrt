#!/usr/bin/env bash
# Fails on relative Markdown links that point at files which do not exist.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import pathlib, re, sys

bad = []
for md in pathlib.Path('.').rglob('*.md'):
    if any(part.startswith('.') for part in md.parts):
        continue
    if '.build' in md.parts:
        continue
    # Vendored third-party packages ship their own docs; their links are not ours.
    if 'Packages' in md.parts:
        continue
    text = md.read_text(errors='ignore')
    for match in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', text):
        target = match.group(1).strip().split('#')[0].strip()
        if not target or target.startswith(('http://', 'https://', 'mailto:', '<')):
            continue
        path = (md.parent / target).resolve()
        if not path.exists():
            bad.append(f"{md}: {target}")
for entry in sorted(set(bad)):
    print(entry)
sys.exit(1 if bad else 0)
PY
