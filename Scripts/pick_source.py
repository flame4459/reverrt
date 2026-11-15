#!/usr/bin/env python3
"""Score downloaded source images, pick the best side view per bike, and turn
the winner into a high-resolution studio sprite.

The score is deliberately mechanical: a side elevation is wide, has two
similar-sized wheels, a sensible wheelbase/diameter ratio, and fills a
reasonable part of the frame. 3/4 views, riders, stands and detail crops fall
out. The contact sheet is then for human review of the top pick.

Usage:
    python3 Scripts/pick_source.py --assets bike-1098 bike-zx-6r
    python3 Scripts/pick_source.py --all
    python3 Scripts/pick_source.py --assets bike-1098 --no-process
"""

from __future__ import annotations

import argparse
import csv
import math
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import parts  # noqa: E402
import pixel_art_bikes as P  # noqa: E402
from render_meshes import keyline  # noqa: E402

SOURCES = ROOT / "pilot" / "sources"
FINAL = SOURCES / "final"
REVIEW = SOURCES / "review"
CUTOUT = ROOT / ".tools" / "cutout"
if not CUTOUT.exists():
    CUTOUT = Path("/tmp/cutout")

SCORES = SOURCES / "scores.csv"
CHOICES = SOURCES / "choices.csv"


def cut_out(path: Path) -> Image.Image | None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "cut.png"
        try:
            result = subprocess.run([str(CUTOUT), str(path), str(out)],
                                    capture_output=True, timeout=45)
        except Exception:
            return None
        if result.returncode != 0 or not out.exists():
            return None
        try:
            return Image.open(out).convert("RGBA")
        except Exception:
            return None


def find_wheels_flex(image: Image.Image) -> list:
    """Like parts.find_wheels, but the radius floor is low enough for a 1000 px
    press photo where the front tyre is only ~10% of the frame height."""
    dark, (x0, y0, x1, y1) = parts._dark_mask(image)
    h, w = y1 - y0, x1 - x0
    ang = np.linspace(0, 2 * math.pi, 64, endpoint=False)
    ca, sa = np.cos(ang), np.sin(ang)
    found = []
    for side, (lo, hi) in (("rear", (x0, x0 + w * 0.45)),
                           ("front", (x0 + w * 0.55, x1))):
        best = None
        for cy in range(int(y0 + h * 0.5), y1 + 1, 4):
            for cx in range(int(lo), int(hi) + 1, 4):
                for r in range(int(h * 0.08), int(h * 0.36), 2):
                    px = (cx + r * ca).astype(int)
                    py = (cy + r * sa).astype(int)
                    ok = (px >= 0) & (px < image.width) & (py >= 0) & (py < image.height)
                    if ok.sum() < 50:
                        continue
                    value = dark[py[ok], px[ok]].mean()
                    if value > 0.82 and abs(cx - (lo + hi) / 2) < w * 0.25:
                        value -= 0.0006 * abs(r - int(h * 0.22))
                        if best is None or value > best[0]:
                            best = (value, cx, cy, r)
        if best:
            found.append((side, best[1], best[2], best[3]))
    return found


def score(path: Path) -> dict | None:
    cut = cut_out(path)
    if cut is None:
        return None
    alpha = np.asarray(cut)[..., 3] > 40
    if not alpha.any():
        return None
    ys, xs = np.nonzero(alpha)
    w = int(xs.max() - xs.min() + 1)
    h = int(ys.max() - ys.min() + 1)
    aspect = w / max(h, 1)
    coverage = float(alpha.mean())
    center = abs(((xs.min() + xs.max()) / 2) - cut.width / 2) / max(cut.width, 1)

    small = cut.resize((520, max(2, round(cut.height * 520 / cut.width))), Image.BOX)
    wheels = find_wheels_flex(small)
    wheels.sort(key=lambda item: item[1])
    count = len(wheels)
    wb_ratio = ratio = y_balance = 0.0
    if count >= 2:
        rear, front = wheels[0], wheels[-1]
        diameter = (rear[3] + front[3]) / 2
        wb_ratio = abs(front[1] - rear[1]) / max(diameter, 1)
        ratio = front[3] / max(rear[3], 1)
        y_balance = abs(front[2] - rear[2]) / max(diameter, 1)

    def bell(value, target, sigma):
        return math.exp(-((value - target) / sigma) ** 2)

    aspect_score = bell(aspect, 1.9, 0.40)
    wheel_score = 1.0 if count >= 2 else (0.25 if count == 1 else 0.0)
    # A real side elevation has wheelbase/diameter ~2.3-2.6; a 3/4 view
    # foreshortens the wheelbase toward 1.2-1.8.
    wb_score = bell(wb_ratio, 2.4, 0.45) if count >= 2 else 0.0
    balance = bell(ratio, 1.0, 0.22) if count >= 2 else 0.0
    level = bell(y_balance, 0.0, 0.10) if count >= 2 else 0.0
    resolution = min(1.0, cut.width / 1200.0)
    fill = 1.0 if 0.18 <= coverage <= 0.65 else 0.45
    centering = max(0.0, 1.0 - center * 5.0)

    total = (0.18 * aspect_score + 0.20 * wheel_score + 0.24 * wb_score
             + 0.10 * balance + 0.10 * level + 0.08 * resolution
             + 0.05 * fill + 0.05 * centering)
    return {
        "score": round(total, 3), "aspect": round(aspect, 2),
        "width": cut.width, "height": cut.height, "coverage": round(coverage, 3),
        "wheels": count, "wb": round(wb_ratio, 2), "balance": round(ratio, 2),
        "level": round(y_balance, 2),
        "center": round(center, 3), "cut": cut,
    }


def clean_sprite(cut: Image.Image) -> Image.Image:
    a = np.asarray(cut).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    mask = alpha > 240
    if not mask.any():
        return cut
    eroded = ndimage.binary_erosion(mask, iterations=1)
    indices = ndimage.distance_transform_edt(
        ~eroded, return_distances=False, return_indices=True)
    rgb = rgb[tuple(indices)]
    alpha = np.where(eroded, 255, 0).astype(np.uint8)
    cleaned = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")
    ys, xs = np.nonzero(alpha > 30)
    cleaned = cleaned.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

    # Keep the app's front-wheel-right convention: the highest point of a side
    # view is normally the screen / bars at the front.
    arr = np.asarray(cleaned)[..., 3] > 40
    cols = np.nonzero(arr.any(axis=0))[0]
    top_x = None
    for row in range(arr.shape[0]):
        found = np.nonzero(arr[row])[0]
        if found.size:
            top_x = found.mean()
            break
    if top_x is not None and top_x < cleaned.width / 2:
        cleaned = cleaned.transpose(Image.FLIP_LEFT_RIGHT)

    cleaned = cleaned.filter(ImageFilter.MedianFilter(3))
    width = 340
    height = max(2, round(cleaned.height * width / cleaned.width))
    small = cleaned.resize((width, height), Image.BOX)
    flat = (small.convert("RGB")
            .quantize(colors=12, method=Image.MEDIANCUT, dither=Image.Dither.NONE)
            .convert("RGB"))
    sprite = flat.convert("RGBA")
    sprite.putalpha(small.getchannel("A").point(lambda v: 255 if v > 128 else 0))
    # Internal ink lines: the sprite language has a keyline plus panel breaks.
    grey = np.asarray(sprite.convert("L"), dtype=np.float32)
    mask = np.asarray(sprite)[..., 3] > 0
    edges = np.zeros_like(mask)
    edges[:, :-1] |= np.abs(np.diff(grey, axis=1)) > 22
    edges[:-1, :] |= np.abs(np.diff(grey, axis=0)) > 22
    edges &= mask
    arr = np.asarray(sprite).copy()
    arr[edges] = [10, 10, 14, 255]
    sprite = Image.fromarray(arr, "RGBA")
    return keyline(sprite)


def studio(sprite: Image.Image, size=(1536, 1024), scale=3) -> Image.Image:
    big = sprite.resize((sprite.width * scale, sprite.height * scale), Image.NEAREST)
    W, H = size
    bg = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        c = tuple(int(84 + 10 * t) for _ in range(3))
        d.line([(0, y), (W, y)], fill=c)
    s = min((W * 0.9) / big.width, (H * 0.8) / big.height)
    image = big.resize((int(big.width * s), int(big.height * s)), Image.LANCZOS)
    x = (W - image.width) // 2
    y = int(H * 0.89) - image.height
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([x + image.width * 0.06, y + image.height * 0.94,
                x + image.width * 0.94, y + image.height * 1.0],
               fill=(20, 22, 26, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    out = Image.alpha_composite(bg, shadow)
    out.alpha_composite(image, (x, y))
    return out.convert("RGB")


def sheet(rows: list[dict], out: Path, cols: int = 5, cell=(320, 240)) -> None:
    rows_n = (len(rows) + cols - 1) // cols
    canvas = Image.new("RGB", (cols * cell[0], rows_n * (cell[1] + 22)), (10, 13, 20))
    draw = ImageDraw.Draw(canvas)
    for index, row in enumerate(rows):
        image = row.get("final") or row.get("cut")
        if image is None:
            continue
        thumb = image.copy()
        thumb.thumbnail((cell[0] - 12, cell[1] - 12))
        x = (index % cols) * cell[0] + (cell[0] - thumb.width) // 2
        y = (index // cols) * (cell[1] + 22) + (cell[1] - thumb.height) // 2
        if thumb.mode == "RGBA":
            canvas.paste(thumb, (x, y), thumb)
        else:
            canvas.paste(thumb, (x, y))
        draw.text(((index % cols) * cell[0] + 6,
                   (index // cols) * (cell[1] + 22) + cell[1] + 4),
                  f"{row['asset'][:28]}  {row['score']:.2f}", fill=(150, 200, 210))
    canvas.save(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", nargs="*")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--no-process", action="store_true")
    parser.add_argument("--min-score", type=float, default=0.45)
    args = parser.parse_args()

    if args.assets:
        assets = args.assets
    else:
        assets = sorted(p.name for p in SOURCES.iterdir()
                        if p.is_dir() and p.name not in {"final", "review"})
    FINAL.mkdir(parents=True, exist_ok=True)
    REVIEW.mkdir(parents=True, exist_ok=True)

    score_rows, choice_rows, best_rows = [], [], []
    for asset in assets:
        folder = SOURCES / asset
        candidates = sorted(folder.glob("*.jpg"))
        if not candidates:
            continue
        scored = []
        for path in candidates:
            info = score(path)
            if info is None:
                continue
            info.update({"asset": asset, "path": str(path.relative_to(ROOT))})
            scored.append(info)
        if not scored:
            print(f"{asset}: no usable candidates")
            continue
        scored.sort(key=lambda item: item["score"], reverse=True)
        for item in scored:
            score_rows.append({k: item[k] for k in
                               ("asset", "path", "score", "aspect", "width", "height",
                                "coverage", "wheels", "wb", "balance", "level", "center")})
        top = scored[:4]
        sheet([{ "asset": asset, "score": item["score"], "cut": item["cut"]}
               for item in top], REVIEW / f"{asset}.png", cols=4, cell=(320, 240))
        best = scored[0]
        choice_rows.append({
            "asset": asset, "path": best["path"], "score": best["score"],
            "aspect": best["aspect"], "wheels": best["wheels"],
            "wb": best["wb"], "level": best["level"], "flag": "" if best["score"] >= args.min_score else "review",
        })
        row = {"asset": asset, "score": best["score"], "cut": best["cut"]}
        if not args.no_process:
            sprite = clean_sprite(best["cut"])
            sprite.resize((sprite.width * 3, sprite.height * 3), Image.NEAREST).save(
                FINAL / f"{asset}-sprite.png")
            final = studio(sprite)
            final.save(FINAL / f"{asset}.png")
            row["final"] = final
        best_rows.append(row)
        print(f"{asset}: {best['path']} score={best['score']:.2f} "
              f"aspect={best['aspect']:.2f} wheels={best['wheels']}")

    with SCORES.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(score_rows[0].keys()) if score_rows else
                                ["asset", "path", "score"])
        writer.writeheader()
        writer.writerows(score_rows)
    with CHOICES.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(choice_rows[0].keys()) if choice_rows else
                                ["asset", "path", "score", "aspect", "wheels", "wb", "level", "flag"])
        writer.writeheader()
        writer.writerows(choice_rows)
    if best_rows:
        sheet(best_rows, SOURCES / "best-sheet.png")
        print(f"{len(best_rows)} picks -> {SOURCES / 'best-sheet.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
