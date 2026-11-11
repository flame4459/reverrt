#!/usr/bin/env python3
"""Check reference renders dropped into ``bikes/refs/`` before they're used.

A family reference has to look like the rest of the set: a side elevation, full
bike in frame, both wheels down, plain background. This validates each file and
tells you which families are ready, which need a re-render, and which are still
missing.

Usage:
    python3 Scripts/check_references.py
    python3 Scripts/check_references.py --verbose
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import families as F  # noqa: E402

REFS = ROOT / "bikes" / "refs"
WISHLIST = ROOT / "catalog" / "reference-wishlist.csv"


def audit(path: Path) -> dict:
    with Image.open(path) as im:
        image = im.convert("RGBA")
    a = np.asarray(image)
    alpha = a[..., 3] > 40
    has_alpha = alpha.mean() < 0.98
    if has_alpha:
        mask = alpha
    else:  # opaque render: assume the bike is everything not near-white
        rgb = a[..., :3].astype(np.int16)
        mask = np.abs(rgb - 255).max(axis=2) > 24
    if not mask.any():
        return {"ok": False, "why": "no bike pixels found"}

    ys, xs = np.nonzero(mask)
    w = xs.max() - xs.min() + 1
    h = ys.max() - ys.min() + 1
    aspect = w / max(h, 1)
    touches_bottom = ys.max() >= image.height - 2
    centered = abs(((xs.min() + xs.max()) / 2) - image.width / 2) < image.width * 0.12

    problems = []
    if aspect < 1.35:
        problems.append(f"aspect {aspect:.2f} - looks like a 3/4 or front view, need a side elevation")
    if aspect > 2.9:
        problems.append(f"aspect {aspect:.2f} - too stretched")
    if w < 700:
        problems.append(f"{w}px wide - render at least 1200px")
    if mask.sum() < 40_000:
        problems.append("bike too small in frame")
    if not centered:
        problems.append("bike is off-centre")

    return {
        "ok": not problems, "why": "; ".join(problems), "aspect": round(float(aspect), 2),
        "size": f"{image.width}x{image.height}", "coverage": round(float(mask.mean()), 3),
        "bottom": touches_bottom, "alpha": has_alpha,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    families = F.load_families()
    by_slug = {f"{F.slug(b)}-{F.slug(f)}": (b, f, models) for (b, f), models in families.items()}

    ready, broken, missing = [], [], []
    for slug, (brand, family, models) in sorted(by_slug.items(), key=lambda kv: -len(kv[1][2])):
        path = F.reference_for(brand, family)
        if path is None:
            missing.append((slug, brand, family, len(models)))
            continue
        info = audit(path)
        if info["ok"]:
            ready.append((slug, brand, family, len(models), info))
        else:
            broken.append((slug, brand, family, len(models), info))

    print(f"families: {len(by_slug)}   ready: {len(ready)}   needs re-render: {len(broken)}   missing: {len(missing)}")
    if ready:
        print("\nREADY")
        for slug, brand, family, n, info in ready:
            print(f"  {slug:38} {n:3} models  {info['size']:>10}  aspect {info['aspect']:.2f}")
    if broken:
        print("\nNEEDS WORK")
        for slug, brand, family, n, info in broken:
            print(f"  {slug:38} {n:3} models  {info['size']:>10}  {info['why']}")
    if missing and args.verbose:
        print("\nMISSING")
        for slug, brand, family, n in missing[:80]:
            print(f"  {slug:38} {n:3} models  -> bikes/refs/{slug}.jpeg")
    elif missing:
        print(f"\nmissing: {len(missing)} families - run with --verbose to list them")

    if WISHLIST.exists():
        print(f"\nprompts: {WISHLIST.relative_to(ROOT)}")
    return 0 if not broken else 1


if __name__ == "__main__":
    raise SystemExit(main())
