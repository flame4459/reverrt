#!/usr/bin/env python3
"""Copy the finished sprites into the generator's pixel idiom and verify them.

Every asset in ``BikeSprites.xcassets`` is a ~1200 px render. This script
re-renders each one on the generator's logical grid (170 px wide, flat palette,
hard alpha) and measures how closely the copy matches the source, so the
generator's output can be checked against the hand-finished baseline rather
than eyeballed.

Usage:
    python3 Scripts/copy_reference_sprites.py
    python3 Scripts/copy_reference_sprites.py --width 170 --colors 32
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import pixel_art_bikes as P  # noqa: E402

ASSETS = ROOT / "revert" / "BikeSprites.xcassets"
OUT = ROOT / "pilot" / "copies"


def fidelity(reference: Image.Image, copy: Image.Image) -> tuple[float, float]:
    """Mean absolute error and opaque-pixel overlap, comparing at logical size."""
    ref = reference.convert("RGBA").crop(P.content_bbox(reference)).resize(copy.size, Image.LANCZOS)
    a = np.asarray(ref).astype(np.int16)
    b = np.asarray(copy).astype(np.int16)
    mask = (a[..., 3] > 0) | (b[..., 3] > 0)
    if not mask.any():
        return 0.0, 0.0
    diff = np.abs(a[..., :3] - b[..., :3])[mask]
    mae = float(diff.mean())
    overlap = float(((a[..., 3] > 0) & (b[..., 3] > 0)).sum()) / max(1, mask.sum())
    return mae, overlap


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=int, default=170)
    parser.add_argument("--colors", type=int, default=32)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--scale", type=int, default=7)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    sources = sorted(ASSETS.glob("*.imageset/*.png"))
    if not sources:
        print("no sprites found", file=sys.stderr)
        return 1

    results = []
    for path in sources:
        original = Image.open(path).convert("RGBA")
        copy = P.pixelate(original, width=args.width, colors=args.colors)
        copy.save(args.out / f"{path.stem}.png")
        mae, overlap = fidelity(original, copy)
        results.append((path.stem, copy.size, len(P.palette_of(copy)), mae, overlap))

    print(f"{'sprite':26} {'size':>9} {'colours':>7} {'MAE':>6} {'overlap':>8}")
    print("-" * 62)
    for name, size, colours, mae, overlap in results:
        print(f"{name:26} {size[0]:>4}x{size[1]:<4} {colours:>7} {mae:>6.1f} {overlap:>7.1%}")
    mae_all = float(np.mean([r[3] for r in results]))
    print("-" * 62)
    print(f"{'mean':26} {'':>9} {'':>7} {mae_all:>6.1f}   across {len(results)} sprites")

    # Proof sheet: originals over copies.
    picks = ["bike-cbr1000rr", "bike-cbr929rr", "bike-cb1000r", "bike-vfr800",
             "bike-cbr600rr", "bike-cb125r-naked"]
    picks = [p for p in picks if (args.out / f"{p}.png").exists()][:6] or [r[0] for r in results[:6]]

    cell_w, row_h, gap, margin, label_h = 480, 150, 16, 20, 22
    width = margin * 2 + cell_w * 3 + gap * 2
    height = margin * 2 + (row_h * 2 + gap + label_h) * 2
    sheet = Image.new("RGB", (width, height), (10, 13, 20))
    from PIL import ImageDraw

    draw = ImageDraw.Draw(sheet)
    for index, name in enumerate(picks):
        column, row = index % 3, index // 3
        x = margin + column * (cell_w + gap)
        y = margin + row * (row_h * 2 + gap + label_h)
        original = Image.open(ASSETS / f"{name}.imageset" / f"{name}.png").convert("RGBA")
        copy = Image.open(args.out / f"{name}.png").convert("RGBA")

        for offset, image, tag in ((0, original, "source render"), (row_h + 4, copy, "generator copy")):
            scale = min(cell_w / image.width, row_h / image.height)
            thumb = image.resize(
                (max(1, int(image.width * scale)), max(1, int(image.height * scale))),
                Image.LANCZOS if offset == 0 else Image.NEAREST,
            )
            sheet.paste(thumb, (x + (cell_w - thumb.width) // 2, y + offset), thumb)
        draw.text((x, y + row_h * 2), f"{name[5:]}  ·  {tag_note(results, name)}", fill=(120, 132, 148))

    sheet.save(ROOT / "pilot" / "copy-proof.png")
    print(f"\nproof sheet -> pilot/copy-proof.png")
    return 0


def tag_note(results, name: str) -> str:
    for candidate, size, colours, mae, overlap in results:
        if candidate == name:
            return f"{colours} colours, MAE {mae:.1f}"
    return ""


if __name__ == "__main__":
    raise SystemExit(main())
