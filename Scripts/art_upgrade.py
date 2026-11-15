#!/usr/bin/env python3
"""Build a per-bike image-to-image pack for upgrading the 406 px sprites.

Each bike keeps its own identity: the existing sprite is the structure/control
image, so the generated art follows that bike's silhouette, proportions and
livery instead of borrowing a family template.

Output (pilot/upgrade by default):
    init/<asset>.png       sprite on a neutral studio field, ready as img2img init
    control/<asset>.png    white line-art of the silhouette, panels and wheels
    prompts.csv            asset, prompt, negative prompt, file paths
    README.md              settings for ComfyUI / A1111 / an external artist

A typical run is ControlNet line-art at weight 0.8-1.0, img2img denoise 0.45-0.65,
three seeds, 1024x768. Then review with a silhouette check against the source.

Usage:
    python3 Scripts/art_upgrade.py pack --limit 24
    python3 Scripts/art_upgrade.py pack --assets bike-1098 bike-cb1000r
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "revert" / "BikeSprites.xcassets"
PACK = ROOT / "catalog" / "sprite-prompts.csv"
OUT = ROOT / "pilot" / "upgrade"
SIZE = (1024, 768)
MARGIN = 0.07

STYLE = (
    "side elevation, full bike in frame, "
    "both wheels touching the ground, front wheel to the right, detailed factory "
    "livery and decals, soft studio lighting, plain light grey background, "
    "no rider, no watermark, no text artifacts, game-ready sprite"
)
NEGATIVE = (
    "3/4 view, front view, rear view, rider, helmet, stand, cropped, cut off, "
    "extra wheels, missing wheels, distorted wheels, blurry, low resolution, "
    "watermark, signature, gibberish text, duplicate bike"
)


def source(asset: str) -> Image.Image | None:
    path = ASSETS / f"{asset}.imageset" / f"{asset}.png"
    if not path.exists():
        return None
    return Image.open(path).convert("RGBA")


def fit(image: Image.Image) -> tuple[Image.Image, tuple[int, int]]:
    """Fit the bike into the pack canvas, preserving aspect, 1:1 pixels."""
    a = np.asarray(image)[..., 3]
    ys, xs = np.nonzero(a > 30)
    image = image.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    target_w = int(SIZE[0] * (1 - 2 * MARGIN))
    target_h = int(SIZE[1] * (1 - 2 * MARGIN))
    scale = min(target_w / image.width, target_h / image.height)
    new = (max(1, int(image.width * scale)), max(1, int(image.height * scale)))
    return image.resize(new, Image.LANCZOS), new


def init_image(image: Image.Image, resized: Image.Image) -> Image.Image:
    canvas = Image.new("RGBA", SIZE, (128, 128, 128, 255))
    x = (SIZE[0] - resized.width) // 2
    y = (SIZE[1] - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas.convert("RGB")


def control_image(image: Image.Image, resized: Image.Image) -> Image.Image:
    """White field with black lines: silhouette, panel edges and wheel detail."""
    canvas = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    x = (SIZE[0] - resized.width) // 2
    y = (SIZE[1] - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))

    rgb = np.asarray(canvas.convert("RGB")).astype(float)
    alpha = np.asarray(canvas)[..., 3] > 40
    gray = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    # Panel/wheel edges from luminance, plus the silhouette boundary.
    edges = np.zeros_like(alpha)
    edges[:, :-1] |= np.abs(np.diff(gray, axis=1)) > 16
    edges[:-1, :] |= np.abs(np.diff(gray, axis=0)) > 16
    boundary = alpha & ~ndimage.binary_erosion(alpha, iterations=1)
    lines = (edges & alpha) | boundary
    lines = ndimage.binary_dilation(lines, iterations=1)

    out = np.full((SIZE[1], SIZE[0], 3), 255, np.uint8)
    out[lines] = (12, 12, 14)
    return Image.fromarray(out, "RGB")


def prompt_for(row: dict) -> str:
    brand = row["brand"]
    model = row["model"]
    category = row.get("category", "motorcycle")
    return f"high-resolution pixel art illustration of a {brand} {model} {category} motorcycle, {STYLE}"


def pack(limit: int | None, only: list[str], out: Path) -> int:
    rows = list(csv.DictReader(PACK.open()))
    if only:
        wanted = set(only)
        rows = [r for r in rows if r["asset"] in wanted]
    elif limit:
        rows = rows[:limit]

    (out / "init").mkdir(parents=True, exist_ok=True)
    (out / "control").mkdir(parents=True, exist_ok=True)

    written = []
    for row in rows:
        asset = row["asset"]
        im = source(asset)
        if im is None or im.width > 700:  # already a high-res source
            continue
        resized, _ = fit(im)
        init_image(resized, resized).save(out / "init" / f"{asset}.png")
        control_image(im, resized).save(out / "control" / f"{asset}.png")
        written.append({
            "asset": asset,
            "brand": row["brand"],
            "model": row["model"],
            "category": row.get("category", ""),
            "prompt": prompt_for(row),
            "negative": NEGATIVE,
            "init": f"init/{asset}.png",
            "control": f"control/{asset}.png",
            "output": f"out/{asset}.png",
        })

    with (out / "prompts.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(written[0].keys()) if written else
                                ["asset", "brand", "model", "category", "prompt",
                                 "negative", "init", "control", "output"])
        writer.writeheader()
        writer.writerows(written)

    (out / "README.md").write_text(f"""# Per-bike art upgrade pack

{len(written)} bikes. Each one uses **its own** existing 406 px sprite as the
structure image, so the generated art keeps that bike's silhouette, wheelbase
and livery instead of borrowing a family template.

For each row in `prompts.csv`:

* init image: `init/<asset>.png`
* line-art control: `control/<asset>.png`
* output target: `out/<asset>.png`

Suggested settings:

* ControlNet line-art (or canny) weight 0.85-1.0
* img2img denoise 0.45-0.65
* 1024 x 768, 3 seeds per bike
* keep the first result that passes the silhouette check; otherwise re-roll

Prompt is per bike. The negative prompt removes 3/4 views, riders, stands,
watermarks and gibberish text.

After generation, review each image against `init/<asset>.png` (same silhouette,
same wheels, same livery) and only then import it.
""")
    print(f"{len(written)} bikes -> {out.relative_to(ROOT)}")
    print(f"prompts -> {(out / 'prompts.csv').relative_to(ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="pack", choices=["pack"])
    parser.add_argument("--limit", type=int)
    parser.add_argument("--assets", nargs="*")
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()
    return pack(args.limit, args.assets or [], args.out)


if __name__ == "__main__":
    raise SystemExit(main())
