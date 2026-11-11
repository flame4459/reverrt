"""Borrow real components out of the finished renders.

The weakest part of hand-drawn bike art is the hardware: wheels, brake discs,
spokes and tyres carry most of the perceived quality, and the 32 finished
renders already have them at ~300 px across. This module locates a wheel by
circle scoring, crops it to its bounding circle, and pastes it into a vector
raster at any radius, so drawn bodywork can sit on real hardware.
"""

from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "revert" / "BikeSprites.xcassets"

_CACHE: dict[tuple[str, str], Image.Image] = {}


def _dark_mask(image: Image.Image) -> tuple[np.ndarray, tuple[int, int, int, int]]:
    a = np.asarray(image.convert("RGBA"))
    alpha = a[..., 3] > 40
    rgb = a[..., :3].astype(float)
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    ys, xs = np.nonzero(alpha)
    return alpha & (lum < 62), (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def find_wheels(image: Image.Image):
    """Locate both wheels: circle score on the dark tyre, one per half."""
    dark, (x0, y0, x1, y1) = _dark_mask(image)
    h, w = y1 - y0, x1 - x0
    ang = np.linspace(0, 2 * math.pi, 64, endpoint=False)
    ca, sa = np.cos(ang), np.sin(ang)
    found = []
    for side, (lo, hi) in (("rear", (x0, x0 + w * 0.45)), ("front", (x0 + w * 0.55, x1))):
        best = None
        for cy in range(int(y0 + h * 0.55), y1 + 1, 6):
            for cx in range(int(lo), int(hi) + 1, 6):
                for r in range(int(h * 0.12), int(h * 0.34), 3):
                    px = (cx + r * ca).astype(int)
                    py = (cy + r * sa).astype(int)
                    ok = (px >= 0) & (px < image.width) & (py >= 0) & (py < image.height)
                    if ok.sum() < 50:
                        continue
                    score = dark[py[ok], px[ok]].mean()
                    if score > 0.86 and abs(cx - (lo + hi) / 2) < w * 0.25:
                        score -= 0.0008 * abs(r - int(h * 0.22))
                        if best is None or score > best[0]:
                            best = (score, cx, cy, r)
        if best:
            found.append((side, best[1], best[2], best[3]))
    return found


def wheel(name: str, side: str = "front", pad: float = 1.04) -> Image.Image:
    """Cropped wheel, square, centred, alpha preserved."""
    key = (name, side)
    if key in _CACHE:
        return _CACHE[key]
    path = ASSETS / f"{name}.imageset" / f"{name}.png"
    image = Image.open(path).convert("RGBA")
    for found_side, cx, cy, r in find_wheels(image):
        if found_side == side:
            r2 = int(r * pad)
            crop = image.crop((cx - r2, cy - r2, cx + r2, cy + r2))
            _CACHE[key] = crop
            return crop
    raise LookupError(f"no {side} wheel in {name}")


def paste_wheel(raster, wheel_img: Image.Image, cx: float, cy: float, radius: float) -> None:
    """Composite a cropped wheel onto a bike_art.Raster at the given radius."""
    size = max(2, int(round(radius * 2)))
    scaled = wheel_img.resize((size, size), Image.NEAREST)
    arr = np.asarray(scaled)
    mask = arr[..., 3] > 40
    x0, y0 = int(round(cx - radius)), int(round(cy - radius))
    h, w = mask.shape
    sx0, sy0 = max(0, -x0), max(0, -y0)
    dx0, dy0 = max(0, x0), max(0, y0)
    dx1, dy1 = min(raster.w, x0 + w), min(raster.h, y0 + h)
    if dx1 <= dx0 or dy1 <= dy0:
        return
    sub = mask[sy0 : sy0 + (dy1 - dy0), sx0 : sx0 + (dx1 - dx0)]
    colour = arr[sy0 : sy0 + (dy1 - dy0), sx0 : sx0 + (dx1 - dx0), :3]
    region = raster.rgb[dy0:dy1, dx0:dx1]
    region[sub] = colour[sub]
    raster.a[dy0:dy1, dx0:dx1] |= sub
