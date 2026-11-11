"""OEM colourways and livery marks.

Reads ``catalog/oem-colours.csv`` (documented factory paint names and codes,
with approximate hex) and paints a sprite with the brand's factory colour, then
stamps the wordmark and a livery stripe onto the bodywork.

The text is drawn in the sprite's pixel grid so it reads at picker size rather
than blurring into the silhouette.
"""

from __future__ import annotations

import csv
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
COLOURS = ROOT / "catalog" / "oem-colours.csv"
FONT = "/System/Library/Fonts/Supplemental/Avenir Next Condensed.ttc"

_CACHE: dict[str, list[dict]] | None = None


def load() -> dict[str, list[dict]]:
    """brand -> [{name, code, rgb}, ...] in file order (first = primary)."""
    global _CACHE
    if _CACHE is not None:
        return _CACHE
    out: dict[str, list[dict]] = {}
    if COLOURS.exists():
        for row in csv.DictReader(COLOURS.open()):
            hexv = row["hex"].strip().lstrip("#")
            try:
                rgb = tuple(int(hexv[i : i + 2], 16) for i in (0, 2, 4))
            except ValueError:
                continue
            out.setdefault(row["brand"], []).append(
                {"name": row["colourway"].strip(), "code": row["code"].strip(), "rgb": rgb}
            )
    _CACHE = out
    return out


def primary(brand: str) -> tuple[int, int, int] | None:
    entries = load().get(brand)
    return entries[0]["rgb"] if entries else None


def accent(brand: str) -> tuple[int, int, int]:
    entries = load().get(brand) or []
    if len(entries) > 1:
        return entries[1]["rgb"]
    rgb = primary(brand) or (200, 60, 50)
    return tuple(int(c * 0.35) for c in rgb)


def draw_livery(image: Image.Image, brand: str, model: str,
                text: bool = True) -> Image.Image:
    """Stamp the wordmark and a livery stripe onto an already-rendered sprite."""
    if not text:
        return image
    img = image.convert("RGBA")
    a = np.asarray(img)[..., 3]
    ys, xs = np.nonzero(a > 40)
    if ys.size == 0:
        return image
    x0, x1 = xs.min(), xs.max()
    y0, y1 = ys.min(), ys.max()
    w, h = x1 - x0, y1 - y0
    if w < 90 or h < 40:
        return image

    colour = accent(brand)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    size = max(7, int(h * 0.085))
    try:
        font = ImageFont.truetype(FONT, size)
    except OSError:
        font = ImageFont.load_default()

    word = brand.upper().replace("-", "")
    tw = d.textlength(word, font=font)
    if tw > w * 0.42:                     # keep it inside the bodywork
        size = max(6, int(size * (w * 0.42) / tw))
        try:
            font = ImageFont.truetype(FONT, size)
        except OSError:
            font = ImageFont.load_default()
        tw = d.textlength(word, font=font)

    tx = int(x0 + w * 0.30)
    ty = int(y0 + h * 0.70)
    # stripe under the wordmark, in the brand's secondary colour
    d.rectangle([tx - 2, ty + size + 3, tx + tw + 2, ty + size + 5], fill=(*colour, 200))
    for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        d.text((tx + dx, ty + dy), word, font=font, fill=(8, 10, 14, 220))
    d.text((tx, ty), word, font=font, fill=(250, 250, 252, 235))

    return Image.alpha_composite(img, layer)


def apply_to_palette(colours: np.ndarray, rgb: tuple[int, int, int]) -> np.ndarray:
    """Shift a mesh palette's saturated paint toward an OEM colour (HSV rotate)."""
    import colorsys

    t_h, t_s, _ = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    out = colours.astype(np.float32).copy()
    seen: dict[tuple, tuple] = {}
    for i, c in enumerate(colours):
        key = tuple(int(v) for v in c)
        if key not in seen:
            r, g, b = (v / 255 for v in key)
            h, s, v = colorsys.rgb_to_hsv(r, g, b)
            if s > 0.22 and v > 0.12:
                nr, ng, nb = colorsys.hsv_to_rgb(t_h, min(0.95, max(0.5, s)), v)
                seen[key] = (nr * 255, ng * 255, nb * 255)
            else:
                seen[key] = key
        out[i] = seen[key]
    return out
