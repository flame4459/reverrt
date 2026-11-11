#!/usr/bin/env python3
"""Build a 3D mesh for every bike in the catalog.

Each mesh is extruded from the best side-on reference available for that entry:

    1. a family reference render in ``bikes/refs/``   (highest detail)
    2. the entry's own sprite in ``pilot/generated/`` (already brand-correct)

Vertices are quantised to int16 and faces to uint16 so a whole catalog of
meshes stays a reasonable size on disk, and colours are one byte per channel
per face. ``Scripts/render_meshes.py`` turns them back into sprites.

Usage:
    python3 Scripts/build_meshes.py --dry-run
    python3 Scripts/build_meshes.py
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
import photo_mesh as PM  # noqa: E402

PACK = ROOT / "catalog" / "sprite-prompts.csv"
SPRITES = ROOT / "pilot" / "generated"
ORIGINALS = ROOT / "revert" / "BikeSprites.xcassets"
OUT = ROOT / "Meshes3D"


def family_reference(brand: str, model: str, families, lookup) -> Path | None:
    family = lookup.get((brand, model)) or F.infer_family(brand, model, families)
    if not family:
        return None
    return F.reference_for(brand, family)


def source_for(row, families, lookup) -> tuple[Path | None, str]:
    ref = family_reference(row["brand"], row["model"], families, lookup)
    if ref is not None:
        return ref, "family-reference"
    original = ORIGINALS / f"{row['asset']}.imageset" / f"{row['asset']}.png"
    if original.exists():
        return original, "original-render"
    sprite = SPRITES / f"{row['asset']}.png"
    if sprite.exists():
        return sprite, "sprite"
    return None, "none"


def save(path: Path, mesh, columns: int) -> None:
    verts = np.asarray(mesh.vertices, np.float32)
    lo = verts.min(axis=0)
    span = np.maximum(verts.max(axis=0) - lo, 1e-6)
    quantised = ((verts - lo) / span * 65534.0).astype(np.uint16)
    faces = np.array([f[0] for f in mesh.faces], np.uint16)
    colours = np.array([f[1] for f in mesh.faces], np.uint8)
    np.savez_compressed(path, verts=quantised, lo=lo, span=span,
                        faces=faces, colours=colours,
                        columns=np.array([columns], np.uint16))


def load(path: Path):
    data = np.load(path)
    verts = data["verts"].astype(np.float32) / 65534.0 * data["span"] + data["lo"]
    return verts, data["faces"].astype(int), data["colours"].astype(np.uint8)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--columns", type=int, default=100)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()

    rows = list(csv.DictReader(PACK.open()))
    if args.limit:
        rows = rows[: args.limit]

    families = F.load_families()
    lookup = F.build_lookup(families)
    OUT.mkdir(exist_ok=True)

    manifest, built, skipped = [], 0, {}
    for i, row in enumerate(rows, 1):
        source, kind = source_for(row, families, lookup)
        if source is None:
            skipped["no source"] = skipped.get("no source", 0) + 1
            continue
        try:
            with Image.open(source) as image:
                mesh = PM.mesh_from_image(image, columns=args.columns)
        except Exception as exc:
            skipped[str(exc)[:40]] = skipped.get(str(exc)[:40], 0) + 1
            continue

        target = OUT / f"{row['asset']}.npz"
        if not args.dry_run:
            save(target, mesh, args.columns)
        built += 1
        manifest.append({
            "asset": row["asset"], "brand": row["brand"], "model": row["model"],
            "source": str(source.relative_to(ROOT)), "source_kind": kind,
            "faces": len(mesh.faces),
            "mesh": str(target.relative_to(ROOT)),
        })
        if i % 100 == 0:
            print(f"  {i}/{len(rows)} …", flush=True)

    if not args.dry_run and manifest:
        with (ROOT / "catalog" / "mesh-manifest.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(manifest[0].keys()))
            writer.writeheader()
            writer.writerows(manifest)

    total = sum(p.stat().st_size for p in OUT.glob("*.npz")) if OUT.exists() else 0
    print(f"meshes built: {built}   skipped: {sum(skipped.values())}")
    if skipped:
        for reason, count in skipped.items():
            print(f"  {reason}: {count}")
    if built:
        print(f"{OUT.relative_to(ROOT)}: {total / 1024 / 1024:.1f} MB "
              f"({total / built / 1024:.0f} KB each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
