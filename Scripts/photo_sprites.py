#!/usr/bin/env python3
"""Turn sourced photos into sprites: Vision cutout -> side-on scoring -> pixelate.

Real photos are 3/4 views far more often than side elevations, and the app's
art is a side profile. So each candidate is segmented with Apple's Vision
foreground mask, scored on how side-on and well-framed the *cutout* is (not the
photo, which is mostly background), and the best one per family becomes a
sprite at the same 170 px grid as the rest of the set.

Usage:
    python3 Scripts/photo_sprites.py                # all families with candidates
    python3 Scripts/photo_sprites.py --only bmw
    python3 Scripts/photo_sprites.py --dry-run
"""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import families as F  # noqa: E402
import pixel_art_bikes as P  # noqa: E402

CUTOUT = Path("/tmp/cutout")
REFS = ROOT / "refs"
OUT = REFS / "sprites"
MANIFEST = REFS / "sprites-manifest.csv"


def segment(source: Path, destination: Path) -> bool:
    if destination.exists():
        return True
    if not CUTOUT.exists():
        return False
    result = subprocess.run([str(CUTOUT), str(source), str(destination)], capture_output=True)
    return result.returncode == 0 and destination.exists()


def mask_metrics(path: Path) -> dict:
    with Image.open(path) as im:
        alpha = np.asarray(im.convert("RGBA"))[..., 3]
    mask = alpha > 120
    if not mask.any():
        return {"aspect": 0.0, "fill": 0.0, "area": 0.0, "score": -1.0}
    ys, xs = np.nonzero(mask)
    w = xs.max() - xs.min() + 1
    h = ys.max() - ys.min() + 1
    aspect = w / max(h, 1)
    fill = mask.sum() / (w * h)
    # Side profiles are wide and fill their box; 3/4 views are near-square.
    aspect_score = 1.0 - min(abs(aspect - 1.9) / 0.85, 1.0)
    fill_score = min(fill / 0.55, 1.0)
    detail = min(mask.sum() / 200_000.0, 1.0)
    return {
        "aspect": round(float(aspect), 2),
        "fill": round(float(fill), 3),
        "area": int(mask.sum()),
        "score": round(0.60 * aspect_score + 0.25 * fill_score + 0.15 * detail, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", type=str)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--width", type=int, default=170)
    parser.add_argument("--colors", type=int, default=28)
    args = parser.parse_args()

    folders = sorted(p for p in REFS.iterdir() if p.is_dir() and p.name != "sprites")
    if args.only:
        folders = [f for f in folders if args.only.lower() in f.name]

    OUT.mkdir(parents=True, exist_ok=True)
    cut_dir = REFS / "cutouts"
    cut_dir.mkdir(exist_ok=True)

    rows, sprites = [], []
    for folder in folders:
        candidates = sorted(folder.glob("*.jpg"))
        if not candidates:
            continue
        scored = []
        for source in candidates:
            cut = cut_dir / f"{folder.name}-{source.stem}.png"
            if not segment(source, cut):
                continue
            metrics = mask_metrics(cut)
            scored.append((metrics["score"], cut, source, metrics))
        if not scored:
            print(f"{folder.name:38} no cutout")
            continue
        scored.sort(key=lambda s: -s[0])
        score, cut, source, metrics = scored[0]

        with Image.open(cut) as im:
            sprite = P.pixelate(im, width=args.width, colors=args.colors, median=1)
        sprite_path = OUT / f"{folder.name}.png"
        if not args.dry_run:
            sprite.save(sprite_path)

        rows.append(
            {
                "family_slug": folder.name, "score": score,
                "aspect": metrics["aspect"], "fill": metrics["fill"],
                "sprite": str(sprite_path.relative_to(ROOT)),
                "source": str(source.relative_to(ROOT)),
                "cutout": str(cut.relative_to(ROOT)),
            }
        )
        sprites.append((f"{folder.name}  {metrics['aspect']}x{metrics['fill']}", sprite))
        print(f"{folder.name:38} score {score:.2f}  aspect {metrics['aspect']:.2f}  fill {metrics['fill']:.2f}")

    if rows and not args.dry_run:
        with MANIFEST.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

        columns, cw, ch, label = 6, 300, 200, 18
        lines = (len(sprites) + columns - 1) // columns
        sheet = Image.new("RGB", (columns * cw + 12, lines * (ch + label) + 12), (10, 13, 20))
        draw = ImageDraw.Draw(sheet)
        for index, (caption, sprite) in enumerate(sprites):
            thumb = sprite.copy()
            thumb.thumbnail((cw - 12, ch - 12), Image.NEAREST)
            x = 8 + (index % columns) * cw
            y = 6 + (index // columns) * (ch + label)
            sheet.paste(thumb, (x, y), thumb)
            draw.text((x, y + ch - 8), caption[:42], fill=(130, 142, 160))
        sheet.save(ROOT / "pilot" / "photo-sprites-sheet.png")
        print(f"\n{len(sprites)} sprites -> refs/sprites, sheet -> pilot/photo-sprites-sheet.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
