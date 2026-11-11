#!/usr/bin/env python3
"""Turn a side-view sprite into a rotatable 2.5D turntable.

A real 3D scan needs a 3D model. What the sprite set *can* give is a solid
approximation: extrude the side silhouette into a slab whose depth follows a
bike-shaped profile (thin at the wheels, thick through the fairing and engine),
then project it orthographically at any yaw angle with simple depth shading.

The result rotates smoothly through 360 degrees and reads as the same machine,
which is what a "look around your bike" control needs.

Usage:
    python3 Scripts/turntable.py --sprite <png> --frames 24 --out pilot/turntable
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def depth_profile(width: int) -> np.ndarray:
    """Half-depth per column, in sprite pixels: thin wheels, fat middle."""
    x = np.linspace(0.0, 1.0, width)
    bell = np.exp(-((x - 0.52) ** 2) / (2 * 0.20 ** 2))
    nose = 0.35 * np.exp(-((x - 0.03) ** 2) / (2 * 0.06 ** 2))
    tail = 0.30 * np.exp(-((x - 0.97) ** 2) / (2 * 0.05 ** 2))
    return 3.0 + 26.0 * np.clip(bell, 0, 1) + 8.0 * nose + 6.0 * tail


def render(sprite: Image.Image, angle_deg: float, depth_steps: int = 46,
           supersample: int = 3) -> Image.Image:
    """Orthographic projection of the extruded sprite at the given yaw.

    The projection runs at ``supersample`` times the sprite resolution and is
    box-filtered back down, which removes the stair-stepping that made the nose
    look like mush as the bike came round.
    """
    if supersample > 1:
        sprite = sprite.resize(
            (sprite.width * supersample, sprite.height * supersample), Image.NEAREST
        )
    rgba = np.asarray(sprite.convert("RGBA"))
    h, w = rgba.shape[:2]
    alpha = rgba[..., 3] > 40

    half_depth = depth_profile(w)          # per column
    max_depth = float(half_depth.max())

    # Build voxel samples: (x, z) pairs, colour taken from the sprite column.
    zs = np.linspace(-1.0, 1.0, depth_steps)
    xs_idx, z_idx = np.meshgrid(np.arange(w), np.arange(depth_steps), indexing="xy")
    z_real = zs[z_idx] * half_depth[xs_idx]

    a = math.radians(angle_deg)
    cos_a, sin_a = math.cos(a), math.sin(a)

    centre = (w - 1) / 2.0
    screen_x = (xs_idx - centre) * cos_a + z_real * sin_a
    depth = -(xs_idx - centre) * sin_a + z_real * cos_a

    # Sort back-to-front so the nearest surface wins.
    order = np.argsort(depth.ravel())
    sx = np.floor(screen_x.ravel()[order] + 0.5).astype(int)
    dsort = depth.ravel()[order]
    xsort = xs_idx.ravel()[order]
    zsort = z_real.ravel()[order]

    # Fixed canvas so the bike stays centred and the same size every frame.
    out_w = w + 2 * int(max_depth) + 6
    offset = int(max_depth) + 3 + int(centre)

    canvas = np.zeros((h, out_w, 4), np.uint8)
    depth_buf = np.full((h, out_w), -1e9, np.float32)

    # Column colour lookup: use the sprite column colour at the voxel's y row.
    cols = rgba[:, xsort, :3]          # (h, n)
    alphas = alpha[:, xsort]           # (h, n)

    for y in range(h):
        tx = sx + offset
        ok = alphas[y]
        if not ok.any():
            continue
        row_depth = dsort
        better = ok & (row_depth >= depth_buf[y, tx])
        if not better.any():
            continue
        idx = np.nonzero(better)[0]
        depth_buf[y, tx[idx]] = row_depth[idx]
        canvas[y, tx[idx], :3] = cols[y][idx]
        canvas[y, tx[idx], 3] = 255

    # Cheap volume shading: the nearer the surface, the brighter.
    if canvas[..., 3].any():
        span = float(depth_buf[canvas[..., 3] > 0].max() - depth_buf[canvas[..., 3] > 0].min()) or 1.0
        norm = np.clip((depth_buf - (depth_buf.min() if depth_buf.size else 0)) / span, 0, 1)
        factor = 0.72 + 0.38 * norm
        rgb = canvas[..., :3].astype(np.float32) * factor[..., None]
        canvas[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)

    out = Image.fromarray(canvas, "RGBA")
    if supersample > 1:
        out = out.resize(
            (max(1, out.width // supersample), max(1, out.height // supersample)), Image.BOX
        )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sprite", type=Path,
                        default=ROOT / "revert" / "BikeSprites.xcassets" /
                        "bike-cbr929rr.imageset" / "bike-cbr929rr.png")
    parser.add_argument("--frames", type=int, default=24)
    parser.add_argument("--width", type=int, default=170)
    parser.add_argument("--orbit", type=float, default=75.0,
                        help="half-range of the orbit in degrees (180 = full turn)")
    parser.add_argument("--supersample", type=int, default=3)
    parser.add_argument("--out", type=Path, default=ROOT / "pilot" / "turntable")
    args = parser.parse_args()

    import sys
    sys.path.insert(0, str(ROOT / "Scripts"))
    import pixel_art_bikes as P

    source = Image.open(args.sprite)
    base = P.pixelate(source, width=args.width, colors=28, median=1)

    args.out.mkdir(parents=True, exist_ok=True)
    frames = []
    for i in range(args.frames):
        if args.orbit >= 180:
            angle = 360.0 * i / args.frames
        else:
            angle = -args.orbit + (2 * args.orbit) * i / max(args.frames - 1, 1)
        frame = render(base, angle, supersample=args.supersample)
        frame.save(args.out / f"frame-{i:02d}.png")
        frames.append(frame)
        print(f"frame {i:02d}  {angle:6.1f} deg  {frame.size}")

    # Contact sheet + animated preview
    from PIL import ImageDraw

    cols = 8
    cell = 230
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * cell), (10, 13, 20))
    for index, frame in enumerate(frames):
        thumb = frame.copy()
        thumb.thumbnail((cell - 10, cell - 10), Image.NEAREST)
        x = (index % cols) * cell + (cell - thumb.width) // 2
        y = (index // cols) * cell + (cell - thumb.height) // 2
        sheet.paste(thumb, (x, y), thumb)
    sheet.save(ROOT / "pilot" / "turntable-sheet.png")

    gif_frames = [f.convert("RGBA").resize((340, int(340 * f.height / f.width)), Image.NEAREST) for f in frames]
    bg = Image.new("RGBA", gif_frames[0].size, (10, 13, 20, 255))
    composited = []
    for frame in gif_frames:
        layer = bg.copy()
        layer.alpha_composite(frame)
        composited.append(layer.convert("P", palette=Image.ADAPTIVE))
    composited[0].save(ROOT / "pilot" / "turntable.gif", save_all=True,
                       append_images=composited[1:], duration=90, loop=0)
    print(f"\n{len(frames)} frames -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
