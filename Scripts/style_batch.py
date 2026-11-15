#!/usr/bin/env python3
"""Generate high-resolution pixel-art sprites from the catalogue prompts with
the locally trained ``revertstyle`` LoRA, then cut out and compose them.

The LoRA was trained on the 32 finished high-res sprites, so the output follows
that exact style: chunky pixels, black keyline, flat colour blocks, studio grey.

Usage:
    python3 Scripts/style_batch.py --limit 12
    python3 Scripts/style_batch.py --assets bike-1098 bike-zx-6r --seed 7
    python3 Scripts/style_batch.py --all --resume
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "catalog" / "sprite-prompts.csv"
OUT = ROOT / "pilot" / "style-batch"
RAW = OUT / "raw"
FINAL = OUT / "final"
CLI = ROOT / ".tools" / "draw-things-cli"
CUTOUT = ROOT / ".tools" / "cutout"
MODEL = "sd_xl_base_1.0_q6p_q8p.ckpt"
LORA = "revertstyle_600_lora_f32.ckpt"

NEGATIVE = (
    "3/4 view, front view, rear view, rider, helmet, stand, floor, shadow, "
    "reflection, cropped, extra wheels, distorted wheels, blurry, photo, "
    "realistic, smooth gradients, watermark, gibberish text"
)


def rows() -> list[dict]:
    with PACK.open() as handle:
        return list(csv.DictReader(handle))


def prompt_for(row: dict) -> str:
    base = row["prompt"].strip()
    # The workbook prompt already asks for the house style; the trigger puts
    # the LoRA in charge of the finish.
    return f"revertstyle, {base}"


def generate(row: dict, seed: int, steps: int, width: int, height: int,
             lora: str) -> Path:
    RAW.mkdir(parents=True, exist_ok=True)
    out = RAW / f"{row['asset']}.png"
    if out.exists():
        return out
    config = json.dumps({"loras": [{
        "file": lora, "weight": 0.9, "mode": "all",
        "version": "sdxl_base_v0.9",
    }]})
    command = [
        str(CLI), "generate", "--model", MODEL,
        "--prompt", prompt_for(row), "--negative-prompt", NEGATIVE,
        "--width", str(width), "--height", str(height),
        "--steps", str(steps), "--cfg", "7", "--seed", str(seed),
        "--config-json", config, "--output", str(out), "--disable-preview",
    ]
    started = time.time()
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0 or not out.exists():
        raise RuntimeError(f"{row['asset']}: {result.stderr[-400:]}")
    print(f"{row['asset']}: {time.time() - started:.0f}s", flush=True)
    return out


def clean_cutout(path: Path) -> Image.Image:
    tmp = OUT / "cut.png"
    result = subprocess.run([str(CUTOUT), str(path), str(tmp)],
                            capture_output=True)
    if result.returncode != 0 or not tmp.exists():
        raise RuntimeError(f"cutout failed: {path}")
    im = Image.open(tmp).convert("RGBA")
    a = np.asarray(im).astype(np.float32)
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


def studio(sprite: Image.Image, size=(1536, 1024)) -> Image.Image:
    W, H = size
    bg = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        c = tuple(int(84 + 10 * t) for _ in range(3))
        d.line([(0, y), (W, y)], fill=c)
    s = min((W * 0.92) / sprite.width, (H * 0.82) / sprite.height)
    image = sprite.resize((int(sprite.width * s), int(sprite.height * s)),
                          Image.LANCZOS)
    x = (W - image.width) // 2
    y = int(H * 0.9) - image.height
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([x + image.width * 0.04, y + image.height * 0.94,
                x + image.width * 0.96, y + image.height * 1.02],
               fill=(20, 22, 26, 170))
    shadow = shadow.filter(ImageFilter.GaussianBlur(20))
    out = Image.alpha_composite(bg, shadow)
    out.alpha_composite(image, (x, y))
    return out.convert("RGB")


def contact(assets: list[str], out: Path, cols: int = 4) -> None:
    files = [FINAL / f"{a}.png" for a in assets if (FINAL / f"{a}.png").exists()]
    if not files:
        return
    # A 959-image sheet is unreadable; sample evenly for a preview.
    if len(files) > 60:
        step = max(1, len(files) // 60)
        files = files[::step][:60]
        out = out.with_name("contact-sheet-preview.png")
    cell = (380, 280)
    rows_n = (len(files) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * cell[0], rows_n * (cell[1] + 20)), (10, 13, 20))
    draw = ImageDraw.Draw(canvas)
    for index, path in enumerate(files):
        im = Image.open(path).convert("RGB")
        im.thumbnail((cell[0] - 10, cell[1] - 10))
        x = (index % cols) * cell[0] + (cell[0] - im.width) // 2
        y = (index // cols) * (cell[1] + 20) + (cell[1] - im.height) // 2
        canvas.paste(im, (x, y))
        draw.text(((index % cols) * cell[0] + 6,
                   (index // cols) * (cell[1] + 20) + cell[1] + 2),
                  path.stem[:30], fill=(140, 200, 210))
    canvas.save(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", nargs="*")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--seed", type=int, default=303)
    parser.add_argument("--steps", type=int, default=26)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=768)
    parser.add_argument("--lora", default=LORA)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--no-post", action="store_true")
    args = parser.parse_args()

    catalogue = rows()
    if args.assets:
        wanted = set(args.assets)
        selected = [r for r in catalogue if r["asset"] in wanted]
    elif args.all:
        selected = catalogue
    else:
        selected = catalogue[: args.limit or 12]

    for index, row in enumerate(selected, 1):
        raw = RAW / f"{row['asset']}.png"
        if args.resume and raw.exists():
            print(f"{row['asset']}: exists", flush=True)
        else:
            try:
                generate(row, args.seed, args.steps, args.width, args.height, args.lora)
            except Exception as exc:
                print(f"FAIL {row['asset']}: {exc}", flush=True)
                continue
        if args.no_post:
            continue
        try:
            sprite = clean_cutout(raw)
            FINAL.mkdir(parents=True, exist_ok=True)
            studio(sprite).save(FINAL / f"{row['asset']}.png")
        except Exception as exc:
            print(f"POST FAIL {row['asset']}: {exc}", flush=True)

    contact([r["asset"] for r in selected], OUT / "contact-sheet.png")
    print(f"{len(selected)} assets -> {OUT.relative_to(ROOT)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
