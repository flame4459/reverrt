#!/usr/bin/env python3
"""Render an 8-frame turntable for every bike.

Full-detail meshes are too heavy to orbit in bulk (15k triangles = 3 s a
frame), so each turntable is built from the bike's sprite at 50 columns -
about 3k triangles, 0.4 s a frame - which is plenty at viewer size.

Output: Turntables/<asset>/frame-00..07.png plus an index for the viewer.

Usage:
    python3 Scripts/build_turntables.py
    python3 Scripts/build_turntables.py --frames 8 --width 320 --limit 5
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import numpy as np
from PIL import Image

import art3d as A
import livery as LV
import photo_mesh as PM
import pixel_art_bikes as P
import render_meshes as RM

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "pilot" / "generated"
OUT = ROOT / "Turntables"
LIGHT = (-0.30, 0.42, 0.85)
FILL = (0.25, 0.45, -0.55)


def render_frames(asset: str, frames: int, width: int, columns: int) -> None:
    with Image.open(SPRITES / f"{asset}.png") as im:
        mesh = PM.mesh_from_image(im, columns=columns)
    height = int(width * 0.68)
    folder = OUT / asset
    folder.mkdir(parents=True, exist_ok=True)
    for i in range(frames):
        yaw = -180.0 + 360.0 * i / frames
        frame = A.render_smooth(mesh, yaw=yaw, size=(width, height), supersample=1,
                                light=LIGHT, fill=FILL)
        sprite = P.pixelate(frame, width=width, colors=32, median=0)
        sprite.save(folder / f"frame-{i:02d}.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument("--width", type=int, default=320)
    parser.add_argument("--columns", type=int, default=110)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--skip-existing", action="store_true")
    args = parser.parse_args()

    rows = list(csv.DictReader((ROOT / "catalog" / "sprite-prompts.csv").open()))
    assets = [r["asset"] for r in rows if (SPRITES / f"{r['asset']}.png").exists()]
    extra = [p.stem for p in (ROOT / "revert" / "BikeSprites.xcassets").glob("*.imageset")]
    assets += [a for a in extra if (OUT / a).exists() is False and a not in assets]
    if args.limit:
        assets = assets[: args.limit]

    OUT.mkdir(exist_ok=True)
    done = 0
    for i, asset in enumerate(assets, 1):
        if args.skip_existing and (OUT / asset / "frame-00.png").exists():
            continue
        try:
            render_frames(asset, args.frames, args.width, args.columns)
            done += 1
        except Exception as exc:
            print(f"  skip {asset}: {exc}", flush=True)
        if i % 20 == 0:
            print(f"  {i}/{len(assets)}", flush=True)

    (OUT / "index.json").write_text(json.dumps({"frames": args.frames, "width": args.width,
                                                "bikes": assets}, indent=1))
    print(f"{done} turntables -> {OUT.relative_to(ROOT)} ({args.frames} frames each)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
