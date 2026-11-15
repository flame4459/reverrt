#!/usr/bin/env python3
"""Install the generated house-style art into BikeSprites.xcassets.

The style batch rendered a grey studio card per bike. The app wants a
transparent sprite, so each card is cut out, trimmed, resized to 800 px and
saved as an indexed PNG with an alpha palette entry. Existing imagesets keep
their Contents.json; only the PNG is replaced.

The 32 hand-finished high-resolution Honda sprites are left untouched.

Usage:
    python3 Scripts/install_style_sprites.py --dry-run
    python3 Scripts/install_style_sprites.py
"""

from __future__ import annotations

import argparse
import csv
import shutil
import subprocess
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "pilot" / "style-batch" / "raw"
CATALOG = ROOT / "revert" / "BikeSprites.xcassets"
CUTOUT = ROOT / ".tools" / "cutout"
BACKUPS = ROOT / "pilot" / "backups"
MANIFEST = ROOT / "pilot" / "style-batch" / "installed.csv"


def cut_out(path: Path) -> Image.Image:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "cut.png"
        result = subprocess.run([str(CUTOUT), str(path), str(out)],
                                capture_output=True)
        if result.returncode != 0 or not out.exists():
            raise RuntimeError("cutout failed")
        image = Image.open(out).convert("RGBA")
    a = np.asarray(image).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    mask = alpha > 240
    eroded = ndimage.binary_erosion(mask, iterations=1)
    indices = ndimage.distance_transform_edt(
        ~eroded, return_distances=False, return_indices=True)
    rgb = rgb[tuple(indices)]
    alpha = np.where(eroded, 255, 0).astype(np.uint8)
    out = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")
    ys, xs = np.nonzero(alpha > 30)
    return out.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def indexed_png(image: Image.Image, edge: int, colors: int) -> Image.Image:
    scale = edge / max(image.size)
    resized = image.resize((max(1, int(image.width * scale)),
                            max(1, int(image.height * scale))), Image.LANCZOS)
    rgb = resized.convert("RGB")
    alpha = resized.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    palette = rgb.quantize(colors=colors, method=Image.MEDIANCUT,
                           dither=Image.Dither.NONE)
    data = palette.getpalette()[: colors * 3] + [0, 0, 0]
    palette.putpalette(data)
    arr = np.asarray(palette).copy()
    arr[np.asarray(alpha) == 0] = colors
    out = Image.fromarray(arr, "P")
    out.putpalette(data)
    out.info["transparency"] = colors
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, default=RAW)
    parser.add_argument("--catalog", type=Path, default=CATALOG)
    parser.add_argument("--edge", type=int, default=800)
    parser.add_argument("--colors", type=int, default=48)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()

    files = sorted(args.raw.glob("*.png"))
    if not files:
        print("no raw style images")
        return 1

    if not args.no_backup and not args.dry_run:
        BACKUPS.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        archive = BACKUPS / f"BikeSprites-before-style-{stamp}.tgz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(args.catalog, arcname="BikeSprites.xcassets")
        print(f"backup -> {archive.relative_to(ROOT)}")

    rows = []
    replaced = skipped = 0
    total_bytes = 0
    for index, path in enumerate(files, 1):
        asset = path.stem
        imageset = args.catalog / f"{asset}.imageset"
        target = imageset / f"{asset}.png"
        if not target.exists():
            print(f"skip {asset}: no imageset")
            skipped += 1
            continue
        try:
            cut = cut_out(path)
            png = indexed_png(cut, args.edge, args.colors)
            if args.dry_run:
                print(f"{asset}: {cut.size} -> {png.size}")
                replaced += 1
                continue
            png.save(target, optimize=True)
            size = target.stat().st_size
            total_bytes += size
            rows.append({
                "asset": asset, "path": str(target.relative_to(ROOT)),
                "width": png.width, "height": png.height, "bytes": size,
            })
            replaced += 1
        except Exception as exc:
            print(f"FAIL {asset}: {exc}")
            skipped += 1
        if index % 100 == 0:
            print(f"  {index}/{len(files)}", flush=True)

    if not args.dry_run and rows:
        with MANIFEST.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)
        print(f"installed {replaced}, skipped {skipped}, "
              f"{total_bytes / 1_000_000:.1f} MB")
        print(f"manifest -> {MANIFEST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
