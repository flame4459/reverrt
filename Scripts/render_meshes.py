#!/usr/bin/env python3
"""Render sprites and turntables from the per-bike meshes in ``Meshes3D``.

Usage:
    python3 Scripts/render_meshes.py --sample 12 --out pilot/mesh-sprites
    python3 Scripts/render_meshes.py --turntable bike-ninja-zx-6r --frames 24
    python3 Scripts/render_meshes.py --all --width 400
"""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

import art3d as A
import livery as LV
import build_meshes as BM
import pixel_art_bikes as P

ROOT = Path(__file__).resolve().parent.parent
MESHES = ROOT / "Meshes3D"
LIGHT = (-0.30, 0.42, 0.85)
FILL = (0.25, 0.45, -0.55)


def load_mesh(asset: str) -> A.Mesh:
    verts, faces, colours = BM.load(MESHES / f"{asset}.npz")
    mesh = A.Mesh()
    mesh.vertices = verts.tolist()
    mesh.faces = [([int(i) for i in face], tuple(int(c) for c in colour))
                  for face, colour in zip(faces, colours)]
    return mesh


def keyline(image: Image.Image, colour=(10, 10, 14)) -> Image.Image:
    a = np.asarray(image.convert("RGBA"))
    mask = a[..., 3] > 40
    grow = mask.copy()
    grow[1:] |= mask[:-1]
    grow[:-1] |= mask[1:]
    grow[:, 1:] |= mask[:, :-1]
    grow[:, :-1] |= mask[:, 1:]
    out = a.copy()
    out[grow & ~mask] = [*colour, 255]
    return Image.fromarray(out, "RGBA")


_BRAND: dict[str, tuple[str, str]] = {}


def brand_of(asset: str) -> tuple[str, str]:
    if not _BRAND:
        import csv
        path = ROOT / "catalog" / "sprite-prompts.csv"
        if path.exists():
            for row in csv.DictReader(path.open()):
                _BRAND[row["asset"]] = (row["brand"], row["model"])
    return _BRAND.get(asset, ("", ""))


def render(asset: str, yaw: float = 0.0, width: int = 400) -> Image.Image:
    mesh = load_mesh(asset)
    frame = A.render_smooth(mesh, yaw=yaw, size=(width * 3, width * 2),
                            supersample=2, light=LIGHT, fill=FILL)
    sprite = P.pixelate(frame, width=width, colors=40, median=0)
    # The extrusion softens silhouettes; a light unsharp pass restores the edge
    # definition without adding pixels.
    sprite = sprite.filter(ImageFilter.UnsharpMask(radius=1.2, percent=140, threshold=2))
    brand, model = brand_of(asset)
    if brand:
        sprite = LV.draw_livery(sprite, brand, model)
    return keyline(sprite)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=int, default=0)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--turntable", type=str)
    parser.add_argument("--frames", type=int, default=24)
    parser.add_argument("--width", type=int, default=400)
    parser.add_argument("--out", type=Path, default=ROOT / "pilot" / "mesh-sprites")
    args = parser.parse_args()

    assets = sorted(p.stem for p in MESHES.glob("*.npz"))
    if args.turntable:
        folder = args.out / f"turntable-{args.turntable}"
        folder.mkdir(parents=True, exist_ok=True)
        progress = range(args.frames)
        for i in progress:
            yaw = -180 + 360.0 * i / args.frames
            render(args.turntable, yaw=yaw, width=args.width).save(folder / f"frame-{i:02d}.png")
            if i % 6 == 0:
                print(f"  frame {i}/{args.frames}", flush=True)
        print(f"{args.frames} frames -> {folder.relative_to(ROOT)}")
        return 0

    if not (args.all or args.sample):
        print(f"{len(assets)} meshes available in {MESHES.relative_to(ROOT)}")
        return 0

    chosen = assets if args.all else assets[: args.sample]
    args.out.mkdir(parents=True, exist_ok=True)
    for i, asset in enumerate(chosen, 1):
        render(asset, width=args.width).save(args.out / f"{asset}.png")
        if i % 25 == 0:
            print(f"  {i}/{len(chosen)}", flush=True)
    print(f"{len(chosen)} sprites -> {args.out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
