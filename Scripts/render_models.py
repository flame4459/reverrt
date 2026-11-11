"""Render sprite art from the 3D model set.

Each class has a CC0/CC-BY mesh in ``Assets3D``. This loads it, orients the
long axis to X so it reads as a side elevation, re-liveries the paint, renders
orthographically at any yaw and pixelates to the app's sprite grid.

Usage:
    python3 Scripts/render_models.py --out pilot/3d-sprites
    python3 Scripts/render_models.py --turntable sport --frames 24
"""

from __future__ import annotations

import argparse
import colorsys
from pathlib import Path

import numpy as np
from PIL import Image

import art3d as A
import glb
import pixel_art_bikes as P

ROOT = Path(__file__).resolve().parent.parent
MODELS = ROOT / "Assets3D"

import livery as LV

def _oem():
    table = {}
    for brand, entries in LV.load().items():
        table[brand.lower().replace("-", "").replace(" ", "")] = entries[0]["rgb"]
    return table

BRANDS = {
    "kawasaki": (104, 190, 58),
    "ducati": (200, 30, 42),
    "harley": (232, 116, 32),
    "bmw": (40, 100, 190),
    "yamaha": (38, 92, 196),
    "honda": (206, 38, 44),
    "triumph": (176, 182, 196),
    "ktm": (232, 120, 26),
}
BRANDS.update({k: v for k, v in _oem().items() if k not in BRANDS})
GREYS = ((28, 28, 32), (92, 92, 102), (186, 190, 200))


def orient(triangles: np.ndarray) -> np.ndarray:
    size = triangles.reshape(-1, 3).max(axis=0) - triangles.reshape(-1, 3).min(axis=0)
    axis = int(np.argmax(size))
    rot = A.rotation("y", 90) if axis == 2 else (A.rotation("z", 90) if axis == 1 else np.eye(3))
    return triangles @ rot.T


def stretch_wheelbase(mesh: A.Mesh, factor: float) -> A.Mesh:
    """Move the wheels apart without distorting them.

    Everything behind the rear axle and ahead of the front axle shifts rigidly,
    so the wheels stay circular; only the middle of the bike stretches. That is
    enough to give one mesh several credible proportions - a short-wheelbase
    supersport versus a long-legged sport tourer.
    """
    verts = np.asarray(mesh.vertices, float)
    xs = verts[:, 0]
    lo, hi = np.percentile(xs, 3), np.percentile(xs, 97)
    span = max(hi - lo, 1e-6)
    shift = (factor - 1.0) * span / 2.0
    t = np.clip((xs - lo) / span, 0.0, 1.0)
    verts[:, 0] = xs + (t * 2.0 - 1.0) * shift
    out = A.Mesh()
    out.vertices = verts.tolist()
    out.faces = mesh.faces
    return out


def recolour(colours: np.ndarray, to_rgb, tolerance: float = 0.10) -> np.ndarray:
    """Paint the dominant livery band in the brand colour, keep the rest.

    Rotating *every* saturated colour collapses two-tone models into one flat
    colour (the adventure mesh went entirely blue). So the dominant hue is found
    first - area weighted - and only colours within ``tolerance`` of it are
    rotated; secondary paints, chrome, seats and tyres survive.

    ``tolerance`` is in hue units (0..1); 0.10 is roughly +/-36 degrees.
    """
    t_h, _, _ = colorsys.rgb_to_hsv(*(c / 255 for c in to_rgb))

    hsv = []
    for colour in colours:
        r, g, b = (v / 255 for v in colour)
        hsv.append(colorsys.rgb_to_hsv(r, g, b))

    # Area-weighted dominant hue among the saturated colours.
    weights: dict[int, float] = {}
    for h, s, v in hsv:
        if s > 0.25 and v > 0.12:
            bucket = int(h * 24)
            weights[bucket] = weights.get(bucket, 0.0) + 1.0
    if not weights:
        return colours.copy()
    dominant = (max(weights, key=weights.get) + 0.5) / 24.0

    out = colours.copy()
    seen: dict[tuple, tuple] = {}
    for i, colour in enumerate(colours):
        key = tuple(np.round(colour).astype(int))
        if key not in seen:
            h, s, v = hsv[i]
            delta = abs((h - dominant + 0.5) % 1.0 - 0.5)
            if s > 0.25 and v > 0.12 and delta <= tolerance:
                nr, ng, nb = colorsys.hsv_to_rgb(t_h, min(0.95, max(0.55, s)), v)
                seen[key] = (nr * 255, ng * 255, nb * 255)
            elif v > 0.86 and s < 0.12:
                nr, ng, nb = colorsys.hsv_to_rgb(t_h, 0.50, 0.94)
                seen[key] = (nr * 255, ng * 255, nb * 255)
            else:
                seen[key] = key
        out[i] = seen[key]
    return out


def load_mesh(name: str, brand: str) -> A.Mesh:
    triangles, colours = glb.load_mesh(MODELS / f"{name}.glb")
    triangles = orient(triangles)
    colours = recolour(colours, BRANDS.get(brand, (190, 60, 50)))
    mesh = A.Mesh()
    verts, faces = [], []
    for tri, colour in zip(triangles, colours):
        base = len(verts)
        verts.extend(tri.tolist())
        faces.append(([base, base + 1, base + 2], tuple(int(v) for v in colour)))
    mesh.vertices = verts
    mesh.faces = faces
    return mesh


def keyline(image: Image.Image, colour=(10, 10, 14)) -> Image.Image:
    """1 px ink edge, matching the installed sprite set."""
    a = np.asarray(image.convert("RGBA"))
    mask = a[..., 3] > 40
    grow = mask.copy()
    grow[1:] |= mask[:-1]
    grow[:-1] |= mask[1:]
    grow[:, 1:] |= mask[:, :-1]
    grow[:, :-1] |= mask[:, 1:]
    out = a.copy()
    out[grow & ~mask] = [*colour, 255]
    return Image.fromarray(out, "RGBA")


def contrast(image: Image.Image, amount: float = 1.12) -> Image.Image:
    a = np.asarray(image).astype(np.float32)
    rgb = (a[..., :3] - 128.0) * amount + 128.0
    a[..., :3] = np.clip(rgb, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def variant_factor(model: str) -> float:
    """Stable per-model proportion, so a family does not all look identical."""
    digest = sum(ord(c) for c in model)
    return 0.94 + (digest % 7) * 0.022       # 0.94 .. 1.07


def sprite(name: str, brand: str, yaw: float = 0.0, width: int = 400,
           model: str | None = None) -> Image.Image:
    mesh = load_mesh(name, brand)
    if model:
        mesh = stretch_wheelbase(mesh, variant_factor(model))
    render = A.render(mesh, yaw=yaw, size=(width * 4, width * 3))
    image = P.pixelate(render, width=width, colors=36, median=1)
    return keyline(contrast(image))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=ROOT / "pilot" / "3d-sprites")
    parser.add_argument("--turntable", type=str)
    parser.add_argument("--frames", type=int, default=24)
    parser.add_argument("--width", type=int, default=400)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)

    if args.turntable:
        from PIL import ImageDraw

        folder = args.out / f"turntable-{args.turntable}"
        folder.mkdir(exist_ok=True)
        frames = []
        for i in range(args.frames):
            yaw = -180 + 360.0 * i / args.frames
            frame = A.render(load_mesh(args.turntable, "kawasaki"), yaw=yaw,
                             size=(900, 640), supersample=2)
            frame.save(folder / f"frame-{i:02d}.png")
            frames.append(frame)
        cols = 8
        cell = 220
        rows = (len(frames) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * cell), (10, 13, 20))
        for i, frame in enumerate(frames):
            t = frame.copy()
            t.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
            sheet.paste(t, ((i % cols) * cell + (cell - t.width) // 2,
                            (i // cols) * cell + (cell - t.height) // 2), t)
        sheet.save(ROOT / "pilot" / f"turntable-{args.turntable}.png")
        print(f"{len(frames)} frames -> {folder}")
        return 0

    combos = [("sport", "kawasaki"), ("sport", "ducati"), ("cruiser", "harley"),
              ("adventure", "bmw"), ("scooter", "yamaha"), ("mini", "honda")]
    for name, brand in combos:
        image = sprite(name, brand, width=args.width)
        image.save(args.out / f"{name}-{brand}.png")
        print(f"{name:10} {brand:10} {image.size}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
