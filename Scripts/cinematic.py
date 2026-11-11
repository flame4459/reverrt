#!/usr/bin/env python3
"""Render a Smash-style challenger reveal for a bike.

Four beats, 24 fps:

  1. blackout with a lightning flash, the bike a dark silhouette
  2. orbit-in: the model swings from 3/4 to side while the camera pushes in
  3. impact: white flash, screen shake, speed lines
  4. title slam: "A NEW CHALLENGER APPROACHES" then the bike name

Usage:
    python3 Scripts/cinematic.py --asset bike-1098 --name "Ducati 1098" --brand ducati
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import art3d as A
import build_meshes as BM

ROOT = Path(__file__).resolve().parent.parent
MESHES = ROOT / "Meshes3D"
FPS = 24
W, H = 640, 360
FONT_DISPLAY = "/System/Library/Fonts/Supplemental/Impact.ttf"
FONT_LABEL = "/System/Library/Fonts/Avenir Next Condensed.ttc"


def load_mesh(asset: str) -> A.Mesh:
    verts, faces, colours = BM.load(MESHES / f"{asset}.npz")
    mesh = A.Mesh()
    mesh.vertices = verts.tolist()
    mesh.faces = [([int(i) for i in face], tuple(int(c) for c in colour))
                  for face, colour in zip(faces, colours)]
    return mesh


def ease_out(t: float) -> float:
    return 1 - (1 - t) ** 3


def ease_in(t: float) -> float:
    return t ** 3


def backdrop(glow: float = 0.0, tint=(20, 90, 140)) -> Image.Image:
    """Dark radial stage, optionally lit by an impact glow."""
    img = Image.new("RGB", (W, H), (6, 8, 12))
    d = ImageDraw.Draw(img)
    if glow > 0:
        for i in range(18, 0, -1):
            r = int(W * (0.10 + 0.055 * i))
            a = glow * (18 - i) / 18
            colour = tuple(int(c * a * 0.5) for c in tint)
            if any(colour):
                d.ellipse([W // 2 - r, H // 2 - r, W // 2 + r, H // 2 + r], fill=colour)
    return img.filter(ImageFilter.GaussianBlur(6))


def vignette(img: Image.Image, strength: float = 0.85) -> Image.Image:
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(60))
    dark = Image.new("RGB", (W, H), (0, 0, 0))
    return Image.composite(img, dark, mask.point(lambda v: int(255 - (255 - v) * strength)))


def speed_lines(img: Image.Image, strength: float, seed: int = 0) -> Image.Image:
    if strength <= 0:
        return img
    rng = np.random.default_rng(seed)
    layer = img.convert("RGBA")
    d = ImageDraw.Draw(layer)
    cx, cy = W / 2, H / 2
    for _ in range(16):
        a = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(0.42, 0.62) * W
        r1 = r0 + rng.uniform(0.10, 0.30) * W
        alpha = int(40 * strength * rng.uniform(0.4, 1.0))
        d.line([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)),
                (cx + r1 * math.cos(a), cy + r1 * math.sin(a))],
               fill=(180, 225, 255, alpha), width=rng.integers(1, 3))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def grade(img: Image.Image) -> Image.Image:
    """Teal shadows, warm highlights - a light cinematic grade."""
    a = np.asarray(img).astype(np.float32) / 255.0
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2])[..., None]
    shadow = np.clip(1.0 - lum * 2.0, 0, 1)
    high = np.clip((lum - 0.45) * 2.0, 0, 1)
    a[..., 2] += 0.05 * shadow[..., 0]        # cool shadows
    a[..., 1] += 0.02 * shadow[..., 0]
    a[..., 0] += 0.06 * high[..., 0]          # warm highlights
    a[..., 1] += 0.02 * high[..., 0]
    a = (a - 0.5) * 1.06 + 0.5                # gentle contrast
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))


def motion_blur(img: Image.Image, length: float, angle: float = 0.0) -> Image.Image:
    """Directional smear for fast movement."""
    if length < 1.2:
        return img
    stamps = []
    for i in range(5):
        off = (i - 2) * length / 4.0
        shifted = img.transform(img.size, Image.AFFINE,
                                (1, 0, off * math.cos(angle), 0, 1, off * math.sin(angle)),
                                resample=Image.BILINEAR)
        stamps.append(np.asarray(shifted).astype(np.float32))
    blended = np.mean(stamps, axis=0).astype(np.uint8)
    return Image.fromarray(blended)


def glow_bloom(img: Image.Image, amount: float = 0.5) -> Image.Image:
    if amount <= 0:
        return img
    bright = img.filter(ImageFilter.GaussianBlur(9))
    return Image.blend(img, Image.blend(img, bright, 0.65), amount)


def add_reflection(img: Image.Image, bike: Image.Image, strength: float = 0.22) -> Image.Image:
    """Mirror the bike under its contact line for a showroom floor."""
    a = np.asarray(bike)[..., 3]
    ys, xs = np.nonzero(a)
    if ys.size == 0 or strength <= 0:
        return img
    ground = int(ys.max())
    flipped = bike.transpose(Image.FLIP_TOP_BOTTOM)
    arr = np.asarray(flipped).astype(np.float32)
    arr[..., 3] *= strength
    flipped = Image.fromarray(arr.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(4))
    offset = 2 * ground - (bike.height - 1)
    img = img.convert("RGBA")
    img.alpha_composite(flipped, (0, offset))
    return img.convert("RGB")


def sparks(img: Image.Image, strength: float, seed: int = 0) -> Image.Image:
    if strength <= 0:
        return img
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = W / 2, H * 0.55
    for _ in range(int(46 * strength)):
        ang = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(20, 80)
        r1 = r0 + rng.uniform(25, 150) * strength
        alpha = int(230 * strength * rng.uniform(0.4, 1.0))
        d.line([(cx + r0 * math.cos(ang), cy + r0 * math.sin(ang)),
                (cx + r1 * math.cos(ang), cy + r1 * math.sin(ang))],
               fill=(255, 214, 120, alpha), width=int(rng.integers(1, 3)))
    return Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")


def bike_frame(mesh: A.Mesh, yaw: float, push: float, exposure: float) -> Image.Image:
    """push 0 = far, 1 = close."""
    margin = 0.34 - 0.23 * push
    frame = A.render_smooth(
        mesh, yaw=yaw, size=(W, H), supersample=1, margin=margin,
        light=(-0.32, 0.46, 0.82), fill=(0.25, 0.45, -0.55), shadow=True,
    )
    if exposure != 1.0:
        arr = np.asarray(frame).astype(np.float32)
        arr[..., :3] = np.clip(arr[..., :3] * exposure, 0, 255)
        frame = Image.fromarray(arr.astype(np.uint8), "RGBA")
    return frame


def compose_text(img: Image.Image, name: str, progress: float, subtitle: str = "") -> Image.Image:
    """Title slam: the headline drops in, then the bike name."""
    layer = img.convert("RGBA")
    d = ImageDraw.Draw(layer)

    if progress > 0.15:
        # headline
        p = min(1.0, (progress - 0.15) / 0.25)
        scale = 1.0 + 1.6 * (1 - ease_out(p))
        size = max(8, int(46 * scale))
        text = "A NEW CHALLENGER"
        try:
            font = ImageFont.truetype(FONT_DISPLAY, size)
        except OSError:
            font = ImageFont.load_default()
        tw = d.textlength(text, font=font)
        if tw > W * 0.88:                       # never let the slam leave frame
            size = max(8, int(size * (W * 0.88) / tw))
            try:
                font = ImageFont.truetype(FONT_DISPLAY, size)
            except OSError:
                pass
            tw = d.textlength(text, font=font)
        x = (W - tw) / 2
        y = H * 0.07 - (1 - ease_out(p)) * 40
        for dx, dy in ((-3, 0), (3, 0), (0, -3), (0, 3), (3, 3), (-3, -3), (2, -2), (-2, 2)):
            d.text((x + dx, y + dy), text, font=font, fill=(8, 10, 16, 255))
        d.text((x, y), text, font=font, fill=(255, 236, 96, 255))

        text2 = "APPROACHES"
        tw2 = d.textlength(text2, font=font)
        for dx, dy in ((-3, 0), (3, 0), (0, -3), (0, 3)):
            d.text(((W - tw2) / 2 + dx, y + size * 0.92 + dy), text2, font=font, fill=(8, 10, 16, 255))
        d.text(((W - tw2) / 2, y + size * 0.92), text2, font=font, fill=(255, 236, 96, 255))

    if progress > 0.45:
        p = min(1.0, (progress - 0.45) / 0.35)
        size = max(8, int(26 + 8 * ease_out(p)))
        try:
            font2 = ImageFont.truetype(FONT_LABEL, size)
        except OSError:
            font2 = ImageFont.load_default()
        tw = d.textlength(name.upper(), font=font2)
        y = H * 0.845
        fade = int(255 * p)
        skew = 12
        d.polygon([((W - tw) / 2 - 22 + skew, y - 5), ((W + tw) / 2 + 22 + skew, y - 5),
                   ((W + tw) / 2 + 22 - skew, y + size + 7), ((W - tw) / 2 - 22 - skew, y + size + 7)],
                  fill=(255, 214, 40, int(235 * p)))
        d.polygon([((W - tw) / 2 - 18 + skew, y - 1), ((W + tw) / 2 + 18 + skew, y - 1),
                   ((W + tw) / 2 + 18 - skew, y + size + 3), ((W - tw) / 2 - 18 - skew, y + size + 3)],
                  fill=(12, 14, 20, int(245 * p)))
        d.text(((W - tw) / 2, y), name.upper(), font=font2, fill=(255, 255, 255, fade))

        if subtitle:
            try:
                font3 = ImageFont.truetype(FONT_LABEL, 13)
            except OSError:
                font3 = ImageFont.load_default()
            tw3 = d.textlength(subtitle.upper(), font=font3)
            d.text(((W - tw3) / 2, y + size + 12), subtitle.upper(), font=font3,
                   fill=(150, 190, 215, int(220 * p)))
    return layer.convert("RGB")


def build(asset: str, name: str, out: Path, subtitle: str = "") -> list[Image.Image]:
    mesh = load_mesh(asset)
    frames: list[Image.Image] = []

    total = 84
    for i in range(total):
        t = i / (total - 1)
        img = backdrop()

        if t < 0.18:                                  # silhouette + flash
            p = t / 0.18
            exposure = 0.18 + 0.25 * p
            yaw = -78 + 18 * p
            bike = bike_frame(mesh, yaw, push=0.15 * p, exposure=exposure)
            img.paste(bike, (0, 0), bike)
            img = add_reflection(img, bike, 0.16)
            img = glow_bloom(img, 0.25)
            if p < 0.22:                              # lightning pop
                flash = 1 - p / 0.22
                img = Image.blend(img, Image.new("RGB", (W, H), (235, 245, 255)), flash * 0.45)
        elif t < 0.68:                                # orbit in
            p = (t - 0.18) / 0.50
            yaw = -60 + 60 * ease_out(p)
            bike = bike_frame(mesh, yaw, push=ease_out(p), exposure=1.0)
            speed = (1 - ease_out(p))
            slide = int(-W * 0.32 * (1 - ease_out(p)))
            if speed > 0.02:
                bike = motion_blur(bike, length=26 * speed, angle=0.0)
            img = backdrop(glow=0.35 + 0.30 * ease_out(p))
            img = speed_lines(img, strength=speed)
            img.paste(bike, (slide, 0), bike)
            img = add_reflection(img, bike, 0.20)
            img = glow_bloom(img, 0.35)
        elif t < 0.78:                                # impact
            p = (t - 0.68) / 0.10
            shake = int(6 * (1 - p))
            bike = bike_frame(mesh, 0.0, push=1.0, exposure=1.25 + 0.6 * (1 - p))
            img = backdrop(glow=0.9 * (1 - p * 0.5))
            img.paste(bike, (shake, shake), bike)
            img = glow_bloom(img, 0.75)
            if p < 0.4:
                img = Image.blend(img, Image.new("RGB", (W, H), (255, 255, 255)),
                                  (1 - p / 0.4) * 0.85)
        else:                                         # title
            p = (t - 0.78) / 0.22
            bike = bike_frame(mesh, 0.0, push=1.0, exposure=1.05)
            img = backdrop(glow=0.45)
            img.paste(bike, (0, 0), bike)
            img = add_reflection(img, bike, 0.22)
            img = glow_bloom(img, 0.30)
            img = compose_text(img, name, p, subtitle)

        img = vignette(img, 0.55)
        img = grade(img)
        frames.append(img)

    out.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames):
        frame.save(out / f"frame-{i:02d}.png")

    palette_frames = [f.convert("P", palette=Image.ADAPTIVE, colors=200) for f in frames]
    gif = out / "challenger.gif"
    palette_frames[0].save(gif, save_all=True, append_images=palette_frames[1:],
                           duration=int(1000 / FPS), loop=0, optimize=True)
    print(f"{len(frames)} frames -> {out}  ({gif.stat().st_size/1024:.0f} KB gif)")
    return frames


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset", default="bike-1098")
    parser.add_argument("--name", default="Ducati 1098")
    parser.add_argument("--subtitle", default="Sportbike · 2007")
    parser.add_argument("--out", type=Path, default=ROOT / "pilot" / "cinematic")
    args = parser.parse_args()
    build(args.asset, args.name, args.out, args.subtitle)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
