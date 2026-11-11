#!/usr/bin/env python3
"""Turn the raw bike art in ``bikes/`` into transparent-animation-ready sprites.

The source art is pixel-art renders saved as JPEG on a flat (or nearly flat)
studio-colour backdrop. The app canvas is near-black, so the backdrop has to
go. For each source file we:

  1. estimate the backdrop colour from the image border,
  2. flood-fill every border-connected region within a colour tolerance,
  3. erode one pixel to drop the JPEG fringe, feather the edge, and
  4. trim to the bike and resize to a sane texture size.

Output is one ``.imageset`` per bike inside ``BikeSprites.xcassets`` so the app
target picks them up through the file-system-synchronized group.

Usage:
    python3 Scripts/import_bike_sprites.py            # write asset catalog
    python3 Scripts/import_bike_sprites.py --dry-run  # report only
    python3 Scripts/import_bike_sprites.py --contact-sheet /tmp/sheet.png
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "bikes"
DEFAULT_CATALOG = ROOT / "revert" / "BikeSprites.xcassets"
ASSET_PREFIX = "bike-"

# Colour distance tolerated when growing the backdrop. Pixel art is flat, so
# this only has to absorb JPEG noise plus the gentle studio gradients.
TOLERANCE = 26
# Longest edge of the exported texture. Hero art renders at ~360 pt on a 3x
# screen (1080 px), so keep a little headroom.
MAX_EDGE = 1200
PAD = 8


def slugify(name: str) -> str:
    """``CB125R naked.jpeg`` -> ``bike-cb125r-naked``."""
    stem = Path(name).stem.lower()
    stem = re.sub(r"[^a-z0-9]+", "-", stem).strip("-")
    return ASSET_PREFIX + stem


def estimate_backdrop(rgb: np.ndarray) -> np.ndarray:
    border = np.concatenate(
        [rgb[0, :, :], rgb[-1, :, :], rgb[:, 0, :], rgb[:, -1, :]], axis=0
    )
    # Quantise so gradient/noise variants of the same backdrop cluster together.
    keys = (border // 8).astype(np.int32)
    keys = keys[:, 0] * 4096 + keys[:, 1] * 64 + keys[:, 2]
    values, counts = np.unique(keys, return_counts=True)
    dominant = values[counts.argmax()]
    return np.median(border[keys == dominant], axis=0)


def backdrop_mask(rgb: np.ndarray, tolerance: int = TOLERANCE) -> np.ndarray:
    """True where a pixel belongs to the border-connected backdrop."""
    bg = estimate_backdrop(rgb)
    distance = np.max(np.abs(rgb.astype(np.int16) - bg.astype(np.int16)), axis=2)
    candidate = distance < tolerance

    labels, count = ndimage.label(candidate)
    if count == 0:
        return np.zeros(rgb.shape[:2], dtype=bool)

    border_labels = np.concatenate(
        [labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]]
    )
    touching = np.unique(border_labels[border_labels > 0])
    return np.isin(labels, touching)


def enclosed_backdrop(rgb: np.ndarray, backdrop: np.ndarray, tolerance: int = 16) -> np.ndarray:
    """Backdrop-coloured regions trapped inside the silhouette.

    Fairings and frames leave windows that the bike surrounds completely, so a
    border flood fill cannot reach them. They read as bright patches on the
    dark canvas, so match the studio colour anywhere inside the bike as well.
    """
    bg = estimate_backdrop(rgb)
    distance = np.max(np.abs(rgb.astype(np.int16) - bg.astype(np.int16)), axis=2)
    candidate = (distance < tolerance) & ~backdrop
    labels, count = ndimage.label(candidate)
    if count == 0:
        return np.zeros_like(backdrop)
    areas = ndimage.sum(candidate, labels, range(1, count + 1))
    keep = np.concatenate([[False], areas >= 4])
    return keep[labels]


def shadow_pixels(rgb: np.ndarray, backdrop: np.ndarray, height: int) -> np.ndarray:
    """Coloured ground shadows cast on the studio floor.

    They are the backdrop colour scaled darker, which a colour match misses and
    which looks like a bruise on the in-app dark canvas. Neutral shadows are
    left alone: they are invisible on the dark canvas and safer to keep.
    """
    bg = estimate_backdrop(rgb).astype(np.float32)
    if np.ptp(bg) < 12:  # neutral backdrop -> neutral shadow, leave it
        return np.zeros_like(backdrop)

    pixels = rgb.astype(np.float32)
    scale = (pixels @ bg) / max(float(bg @ bg), 1.0)
    residual = np.max(np.abs(pixels - scale[..., None] * bg), axis=2)
    band = np.zeros(backdrop.shape, dtype=bool)
    band[int(height * 0.82) :] = True
    return band & (scale > 0.3) & (scale < 0.99) & (residual < 20) & ~backdrop


def stray_bottom_fragments(foreground: np.ndarray) -> np.ndarray:
    """Caption text and shadow slivers that sit under the bike.

    They are small, float in the bottom sliver of the frame and are never part
    of the machine.
    """
    height = foreground.shape[0]
    labels, count = ndimage.label(foreground)
    if count == 0:
        return np.zeros_like(foreground)

    drop = np.zeros(count + 1, dtype=bool)
    for index, slices in enumerate(ndimage.find_objects(labels), start=1):
        if slices is None:
            continue
        top = slices[0].start
        area = float((labels[slices] == index).sum())
        if top > height * 0.86 and area < foreground.size * 0.05:
            drop[index] = True
    return drop[labels]



def ground_shadow(foreground: np.ndarray, rgb: np.ndarray) -> np.ndarray:
    """Drop the flat floor shadow some renders paint under the bike.

    Only wide, very flat runs in the bottom sliver of the silhouette qualify:
    that catches a painted floor strip without touching a tyre's contact patch
    or a dark belly pan, both of which are narrow or textured.
    """
    height, width = foreground.shape
    background = estimate_backdrop(rgb).astype(np.float32)
    if float(background @ background) < 1.0:
        return np.zeros_like(foreground)

    pixels = rgb.astype(np.float32)
    scale = (pixels @ background) / float(background @ background)
    residual = np.max(np.abs(pixels - scale[..., None] * background), axis=2)

    rows = np.nonzero(foreground.any(axis=1))[0]
    if rows.size == 0:
        return np.zeros_like(foreground)

    drop = np.zeros_like(foreground)
    for y in range(max(rows.min(), rows.max() - int(height * 0.08)), rows.max() + 1):
        columns = np.nonzero(foreground[y])[0]
        if columns.size < width * 0.45:
            continue
        for run in np.split(columns, np.where(np.diff(columns) > 2)[0] + 1):
            if run.size < width * 0.45:
                continue
            level = float(np.median(scale[y, run]))
            if 0.55 < level < 1.01 and float(np.median(residual[y, run])) < 10:
                drop[y, run] = True
    return drop

def thin_ground_lines(foreground: np.ndarray) -> np.ndarray:
    """Hairline floor/ground rules left at the very bottom of the frame."""
    width = foreground.shape[1]
    labels, count = ndimage.label(foreground)
    if count == 0:
        return np.zeros_like(foreground)

    drop = np.zeros(count + 1, dtype=bool)
    for index, slices in enumerate(ndimage.find_objects(labels), start=1):
        if slices is None:
            continue
        height = slices[0].stop - slices[0].start
        span = slices[1].stop - slices[1].start
        if height <= 3 and span >= width * 0.12:
            drop[index] = True
    return drop[labels]


def matte(path: Path) -> Image.Image:
    source = Image.open(path).convert("RGB")
    rgb = np.asarray(source).astype(np.uint8)

    backdrop = backdrop_mask(rgb)
    holes = enclosed_backdrop(rgb, backdrop) | shadow_pixels(rgb, backdrop, rgb.shape[0])
    # Grow the windows by a couple of pixels: the seams between paint and the
    # trapped backdrop are JPEG blends that no flat-colour test catches.
    holes = ndimage.binary_dilation(holes, iterations=2)
    foreground = ~(backdrop | holes)
    foreground = (
        foreground
        & ~ground_shadow(foreground, rgb)
        & ~stray_bottom_fragments(foreground)
        & ~thin_ground_lines(foreground)
    )

    # Erode one pixel: JPEG ringing leaves a fringe of backdrop-coloured pixels
    # along every edge, which would read as a grey halo on the dark canvas.
    foreground = ndimage.binary_erosion(foreground, iterations=1, border_value=0)

    alpha = (foreground.astype(np.uint8)) * 255
    alpha = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.6))

    out = Image.fromarray(rgb, "RGB").convert("RGBA")
    out.putalpha(alpha)
    return bleed_edge_colours(out)


def bleed_edge_colours(image: Image.Image) -> Image.Image:
    """Replace half-transparent edge pixels with their nearest solid colour.

    The blurred alpha leaves a rim of backdrop-coloured pixels at partial
    opacity; composited on a dark canvas those become a pale halo. Copying the
    nearest fully-opaque colour inwards keeps the silhouette clean.
    """
    data = np.asarray(image).astype(np.float32)
    alpha = data[..., 3]
    solid = alpha >= 254
    if not solid.any():
        return image

    indices = ndimage.distance_transform_edt(
        ~solid, return_distances=False, return_indices=True
    )
    nearest = data[indices[0], indices[1], :3]

    edge = (alpha > 0) & ~solid
    data[..., :3] = np.where(edge[..., None], nearest, data[..., :3])
    return Image.fromarray(np.clip(data, 0, 255).astype(np.uint8), "RGBA")


def trim_and_fit(image: Image.Image, max_edge: int = MAX_EDGE, pad: int = PAD) -> Image.Image:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.nonzero(alpha > 8)
    if ys.size == 0:
        return image
    top, bottom = max(ys.min() - pad, 0), min(ys.max() + pad + 1, image.height)
    left, right = max(xs.min() - pad, 0), min(xs.max() + pad + 1, image.width)
    image = image.crop((left, top, right, bottom))

    scale = min(1.0, max_edge / max(image.size))
    if scale < 1.0:
        size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
        image = premultiplied_resize(image, size)
    return image


def premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize RGBA without dragging transparent black into the visible edge."""
    data = np.asarray(image).astype(np.float32) / 255.0
    premultiplied = data.copy()
    premultiplied[..., :3] *= data[..., 3:4]
    scaled = Image.fromarray((premultiplied * 255.0 + 0.5).astype(np.uint8), "RGBA").resize(
        size, Image.LANCZOS
    )
    back = np.asarray(scaled).astype(np.float32) / 255.0
    alpha = back[..., 3:4]
    with np.errstate(invalid="ignore", divide="ignore"):
        unmultiplied = np.where(alpha > 1e-4, back[..., :3] / np.maximum(alpha, 1e-4), 0.0)
    result = np.concatenate([np.clip(unmultiplied, 0, 1), alpha], axis=2)
    return Image.fromarray((result * 255.0 + 0.5).astype(np.uint8), "RGBA")


def write_imageset(image: Image.Image, name: str, catalog: Path) -> Path:
    imageset = catalog / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    png = imageset / f"{name}.png"
    image.save(png, format="PNG", optimize=True)

    contents = {
        "images": [
            {"filename": png.name, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "original"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
    return png


def contact_sheet(items: list[tuple[str, Image.Image]], destination: Path, columns: int = 4) -> None:
    cell_w, cell_h, label_h, margin = 340, 200, 22, 14
    rows = (len(items) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * cell_w + margin, rows * (cell_h + label_h) + margin),
        (10, 13, 19),
    )
    for index, (name, image) in enumerate(items):
        row, column = divmod(index, columns)
        thumb = image.copy()
        thumb.thumbnail((cell_w - margin, cell_h - margin), Image.LANCZOS)
        x = column * cell_w + (cell_w - thumb.width) // 2
        y = row * (cell_h + label_h) + margin // 2 + (cell_h - thumb.height) // 2
        sheet.paste(thumb, (x, y), thumb)
    sheet.save(destination)
    print(f"contact sheet -> {destination}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--contact-sheet", type=Path)
    args = parser.parse_args()

    files = sorted(
        p for p in args.source.iterdir() if p.suffix.lower() in {".jpeg", ".jpg", ".png"}
    )
    if not files:
        print(f"no sprites found in {args.source}", file=sys.stderr)
        return 1

    if not args.dry_run:
        args.catalog.mkdir(parents=True, exist_ok=True)
        info = {"info": {"author": "xcode", "version": 1}}
        (args.catalog / "Contents.json").write_text(json.dumps(info, indent=2) + "\n")

    rendered: list[tuple[str, Image.Image]] = []
    seen: dict[str, str] = {}
    for path in files:
        name = slugify(path.name)
        if name in seen:
            print(f"! duplicate asset name {name}: {path.name} vs {seen[name]}", file=sys.stderr)
        seen[name] = path.name

        image = trim_and_fit(matte(path))
        rendered.append((name, image))
        if args.dry_run:
            print(f"{path.name:28} -> {name:26} {image.width}x{image.height}")
        else:
            png = write_imageset(image, name, args.catalog)
            print(f"{path.name:28} -> {png.relative_to(ROOT)} {image.width}x{image.height}")

    if args.contact_sheet:
        contact_sheet(rendered, args.contact_sheet)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
