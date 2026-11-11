#!/usr/bin/env python3
"""Download the bikez photo for each matched bike, cut it out, pixelate it.

For every row in ``catalog/specs.csv`` with a picture URL:

    1. download the catalogue photo
    2. run the Vision foreground cutout (Scripts/cutout.swift)
    3. pixelate to the app's sprite grid

Output: ``pilot/photos/<asset>.png`` - transparent sprites straight from real
photographs.

Usage:
    python3 Scripts/pull_photos.py --limit 5
    python3 Scripts/pull_photos.py
"""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import pixel_art_bikes as P  # noqa: E402

SPECS = ROOT / "catalog" / "specs.csv"
RAW = ROOT / "refs" / "bikez"
CUT = RAW / "cut"
OUT = ROOT / "pilot" / "photos"
CUTOUT = Path("/tmp/cutout")


def download(url: str, path: Path) -> bool:
    if path.exists() and path.stat().st_size > 2000:
        return True
    result = subprocess.run(
        ["curl", "-sSL", "--max-time", "45", "-A", "Mozilla/5.0", "-o", str(path), url],
        capture_output=True,
    )
    return result.returncode == 0 and path.exists() and path.stat().st_size > 2000


def cutout(source: Path, target: Path) -> bool:
    if target.exists():
        return True
    if not CUTOUT.exists():
        return False
    result = subprocess.run([str(CUTOUT), str(source), str(target)], capture_output=True)
    return result.returncode == 0 and target.exists()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--width", type=int, default=400)
    parser.add_argument("--colors", type=int, default=40)
    args = parser.parse_args()

    rows = [r for r in csv.DictReader(SPECS.open()) if r.get("picture")]
    if args.limit:
        rows = rows[: args.limit]
    print(f"{len(rows)} bikes with a catalogue photo")

    RAW.mkdir(parents=True, exist_ok=True)
    CUT.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)

    ok = failed = 0
    for i, row in enumerate(rows, 1):
        asset = row["asset"]
        raw = RAW / f"{asset}.jpg"
        cut = CUT / f"{asset}.png"
        if not download(row["picture"], raw) or not cutout(raw, cut):
            failed += 1
            continue
        try:
            with Image.open(cut) as im:
                alpha = np.asarray(im.convert("RGBA"))[..., 3]
                if (alpha > 60).sum() < 5000:      # refuse an empty cutout
                    failed += 1
                    continue
                sprite = P.pixelate(im, width=args.width, colors=args.colors, median=1)
            sprite.save(OUT / f"{asset}.png")
            ok += 1
        except Exception:
            failed += 1
        if i % 25 == 0:
            print(f"  {i}/{len(rows)}  ok {ok}  failed {failed}", flush=True)

    print(f"photos ready: {ok}   failed: {failed}   -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
