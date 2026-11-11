#!/usr/bin/env python3
"""Measure a bike's geometry from a side-on reference image.

Produces the handful of numbers that actually distinguish one motorcycle
silhouette from another, all normalised by wheel diameter so they compare
across image sizes:

    wheelbase      axle-to-axle / wheel diameter
    seat_height    seat top / diameter
    tank_height    highest body point / diameter
    tail_height    rear bodywork / diameter
    nose_overhang  how far the front bodywork leads the front axle

Usage:
    python3 Scripts/measure_reference.py refs/cutouts/*.png
    python3 Scripts/measure_reference.py --out catalog/measurements.csv
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

import parts  # noqa: E402


def measure(path: Path) -> dict | None:
    with Image.open(path) as im:
        image = im.convert("RGBA")
    # The ratios are scale invariant, so work small: the circle search is
    # O(pixels) and full-resolution references take minutes each.
    if image.width > 520:
        scale = 520 / image.width
        image = image.resize((520, max(2, int(image.height * scale))), Image.BOX)
    wheels = parts.find_wheels(image)
    if len(wheels) < 2:
        return None
    rear = next(w for w in wheels if w[0] == "rear")
    front = next(w for w in wheels if w[0] == "front")
    rx, ry, rr = rear[1], rear[2], rear[3]
    fx, fy, fr = front[1], front[2], front[3]
    diameter = (rr + fr) / 1.0          # radii sum == one diameter each, averaged

    alpha = np.asarray(image)[..., 3] > 60
    ys, xs = np.nonzero(alpha)
    if ys.size == 0:
        return None
    ground = max(ys)
    top = min(ys)

    def top_at(x0, x1):
        band = alpha[:, max(0, int(x0)) : int(x1)]
        rows = np.nonzero(band.any(axis=1))[0]
        return rows.min() if rows.size else None

    mid_seat = (rx + (fx - rx) * 0.42, rx + (fx - rx) * 0.58)
    seat = top_at(*mid_seat)
    tail = top_at(rx - rr * 0.9, rx + rr * 0.2)
    tank = top_at(rx + (fx - rx) * 0.30, rx + (fx - rx) * 0.55)

    def normalise(y):
        return None if y is None else round((ground - y) / diameter, 2)

    return {
        "file": path.name,
        "wheelbase": round(abs(fx - rx) / diameter, 2),
        "seat_height": normalise(seat),
        "tank_height": normalise(tank),
        "tail_height": normalise(tail),
        "overall_height": round((ground - top) / diameter, 2),
        "nose_overhang": round((xs.max() - (fx + fr)) / diameter, 2),
        "aspect": round((xs.max() - xs.min()) / (ground - top), 2),
        "front_radius": round(fr / rr, 2),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", type=Path)
    parser.add_argument("--out", type=Path, default=ROOT / "catalog" / "measurements.csv")
    args = parser.parse_args()

    files = args.files or sorted((ROOT / "refs" / "cutouts").glob("*.png"))
    rows = []
    for path in files:
        try:
            result = measure(path)
        except Exception as exc:
            print(f"  skip {path.name}: {exc}")
            continue
        if result:
            rows.append(result)
            print(f"{path.name[:46]:48} wb={result['wheelbase']:.2f} "
                  f"seat={result['seat_height']} tank={result['tank_height']} "
                  f"tail={result['tail_height']}")

    if rows:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with args.out.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print(f"\n{len(rows)} measured -> {args.out.relative_to(ROOT)}")

        wb = [r["wheelbase"] for r in rows]
        print(f"wheelbase  min {min(wb):.2f}  median {np.median(wb):.2f}  max {max(wb):.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
