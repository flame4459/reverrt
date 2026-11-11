#!/usr/bin/env python3
"""Stretch each family's meshes to the wheelbase measured from its reference.

The measurement pass (``measure_reference.py``) gives a wheelbase in wheel
diameters per reference image. This maps those onto families, then deforms the
vertices of every mesh in that family so its axle spacing matches - wheels stay
circular because only the region between the axles is scaled.

Usage:
    python3 Scripts/apply_measurements.py --dry-run
    python3 Scripts/apply_measurements.py
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import build_meshes as BM  # noqa: E402
import families as F  # noqa: E402

MEASUREMENTS = ROOT / "catalog" / "measurements.csv"
MESHES = ROOT / "Meshes3D"
BASELINE = 2.55          # typical wheelbase/diameter of the source renders
CLAMP = (0.88, 1.14)


def load_factors() -> dict[str, float]:
    """family slug -> wheelbase stretch factor."""
    if not MEASUREMENTS.exists():
        return {}
    rows = list(csv.DictReader(MEASUREMENTS.open()))
    factors: dict[str, list[float]] = {}
    for row in rows:
        try:
            wb = float(row["wheelbase"])
        except (KeyError, ValueError):
            continue
        if not (1.6 <= wb <= 3.2):
            continue
        slug = "-".join(row["file"].split("-")[:-2])
        factors.setdefault(slug, []).append(wb)
    out = {}
    for slug, values in factors.items():
        wb = float(np.median(values))
        out[slug] = float(np.clip(wb / BASELINE, *CLAMP))
    return out


def stretch(mesh_verts: np.ndarray, factor: float) -> np.ndarray:
    """Move the axles apart, keeping everything outside them rigid."""
    verts = mesh_verts.copy()
    xs = verts[:, 0]
    lo, hi = np.percentile(xs, 3), np.percentile(xs, 97)
    span = max(hi - lo, 1e-6)
    shift = (factor - 1.0) * span / 2.0
    t = np.clip((xs - lo) / span, 0.0, 1.0)
    verts[:, 0] = xs + (t * 2.0 - 1.0) * shift
    return verts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    factors = load_factors()
    print(f"{len(factors)} families with a measured wheelbase")

    family_of = F.build_lookup(F.load_families())
    rows = list(csv.DictReader((ROOT / "catalog" / "sprite-prompts.csv").open()))

    edited, skipped = 0, 0
    by_factor: dict[float, int] = {}
    for row in rows:
        family = family_of.get((row["brand"], row["model"]))
        if not family:
            skipped += 1
            continue
        slug = f"{F.slug(row['brand'])}-{F.slug(family)}"
        factor = factors.get(slug)
        if factor is None or abs(factor - 1.0) < 0.01:
            skipped += 1
            continue

        path = MESHES / f"{row['asset']}.npz"
        if not path.exists():
            skipped += 1
            continue

        if args.dry_run:
            edited += 1
            by_factor[round(factor, 2)] = by_factor.get(round(factor, 2), 0) + 1
            continue

        verts, faces, colours = BM.load(path)
        lo = verts.min(axis=0)
        span = np.maximum(verts.max(axis=0) - lo, 1e-6)
        verts = stretch(verts, factor)
        lo2 = verts.min(axis=0)
        span2 = np.maximum(verts.max(axis=0) - lo2, 1e-6)
        quant = ((verts - lo2) / span2 * 65534.0).astype(np.uint16)
        np.savez_compressed(path, verts=quant, lo=lo2, span=span2,
                            faces=faces.astype(np.uint16),
                            colours=colours.astype(np.uint8),
                            columns=np.array([140], np.uint16))
        edited += 1
        by_factor[round(factor, 2)] = by_factor.get(round(factor, 2), 0) + 1

    print(f"meshes {'would be ' if args.dry_run else ''}edited: {edited}   skipped: {skipped}")
    for factor, count in sorted(by_factor.items()):
        print(f"  x{factor:.2f}  {count} bikes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
