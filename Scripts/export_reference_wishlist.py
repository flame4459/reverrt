#!/usr/bin/env python3
"""Export the reference-art wishlist: one side-profile render per model family.

The generator re-liveries reference art, so what it needs is not 995 renders
but one per *family* - a ZX-6R and a ZX-10R can share a silhouette, a ZX-6R and
a Vulcan cannot. The workbook already defines those families; this script lists
them, with the models each one covers and a ready prompt.

Render each row, save it to the ``ref_filename`` path, and every model in that
family inherits it:

    bikes/refs/kawasaki-ninja-zx.jpeg   ->  25 Ninja models

Usage:
    python3 Scripts/export_reference_wishlist.py
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import families as F  # noqa: E402

OUT = ROOT / "catalog" / "reference-wishlist.csv"
STYLE = (
    "retro NES-style 16-colour palette, chunky clean pixels, "
    "side elevation, full bike in frame, both wheels touching the ground, front wheel to the right, "
    "strong black keyline, flat studio lighting, plain solid background, no rider, no text, no watermark, "
    "no shadow on the floor, game-ready sprite"
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    families = F.load_families()
    rows = []
    for (brand, family), models in families.items():
        ref = F.reference_for(brand, family)
        slug = f"{F.slug(brand)}-{F.slug(family)}"
        rows.append(
            {
                "ref_filename": f"bikes/refs/{slug}.jpeg",
                "brand": brand,
                "family": family,
                "models_covered": len(models),
                "have_reference": "yes" if ref else "",
                "example_models": ", ".join(models[:4]),
                "prompt": (
                    f"8-bit pixel art sprite of a {brand} {family} motorcycle, {STYLE}"
                ),
                "target": "1200 x 800 px, transparent or plain background",
            }
        )

    rows.sort(key=lambda r: (-r["models_covered"], r["brand"]))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    total_models = sum(r["models_covered"] for r in rows)
    have = sum(1 for r in rows if r["have_reference"])
    print(f"{len(rows)} families cover {total_models} workbook models")
    print(f"references already present: {have}")
    print(f"still to render: {len(rows) - have}")
    print(f"-> {args.out.relative_to(ROOT)}")
    print("\nlargest families (most models per reference):")
    for row in rows[:10]:
        print(f"  {row['brand']:16} {row['family']:24} {row['models_covered']:3} models")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
