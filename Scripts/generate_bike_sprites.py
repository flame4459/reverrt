#!/usr/bin/env python3
"""Generate sprites for bikes that have no artwork, in the existing house style.

Instead of drawing a motorcycle from scratch, this takes the finished renders
in ``bike/`` as silhouette templates, copies them to the generator's logical
pixel grid, and re-liveries them for the target brand. The result sits in the
same idiom as the hand-finished art because the silhouette *is* that art.

Category -> template pool:

    Sportbike, Touring  -> the CBR / VFR renders
    Naked, Standard     -> the CB renders

Categories with no reference in the set (cruiser, adventure, scooter, ...) are
skipped and reported: recolouring a Fireblade into a Harley would be wrong.

Usage:
    python3 Scripts/generate_bike_sprites.py --limit 12
    python3 Scripts/generate_bike_sprites.py --dry-run
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import pixel_art_bikes as P  # noqa: E402
import families as F  # noqa: E402
import bike_art as A  # noqa: E402

ASSETS = ROOT / "revert" / "BikeSprites.xcassets"
PACK = ROOT / "catalog" / "sprite-prompts.csv"
OUT = ROOT / "pilot" / "generated"
PHOTOS = ROOT / "pilot" / "photos"

SPORT = ["bike-cbr600rr", "bike-cbr929rr", "bike-cbr1000rr", "bike-cbr954rr",
         "bike-cbr900rr", "bike-cbr600f4i", "bike-vtr1000-sp-1", "bike-cbr650r"]
TOURING = ["bike-vfr1200f", "bike-cbr1100xx", "bike-vfr800f", "bike-vfr800"]
NAKED = ["bike-cb1000r", "bike-cb300r", "bike-cb125r-naked", "bike-cb900f", "bike-cb600f"]

# Categories with no render at all: drawn from code by Scripts/bike_art.py
# Classes rendered from real 3D geometry (Assets3D), which is the only path
# that gives a brand-correct silhouette at any angle.
CLASS_3D: dict[str, str] = {}   # 3D geometry disabled - the meshes looked worse than the derived art

# Photo-derived class templates. These replace the hand-drawn classes: real
# pixels from a photographed bike beat anything the vector engine produced.
CLASS_PHOTO: dict[str, str] = {}   # retired: everything is drawn from code now

# Everything not covered by a family reference is drawn by Scripts/bike_art.py.
CLASS_ART = {
    "Sportbike": "sport",
    "Naked": "naked",
    "Cruiser": "cruiser",
    "Adventure": "adventure",
    "Scooter": "scooter",
    "Touring": "sport",
    "Standard": "naked",
    "Dual-sport": "adventure",
    "Supermoto": "adventure",
    "Mini": "naked",
    "Trike": "cruiser",
}

TEMPLATES = {
    "Sportbike": SPORT,
    "Touring": TOURING,
    "Naked": NAKED,
    "Standard": NAKED,
    "Mini": NAKED,
}

# Body colour per brand. Hue is what matters; saturation is scaled per template.
BRAND_COLOURS = {
    "Honda": (206, 38, 44),
    "Yamaha": (38, 92, 196),
    "Kawasaki": (104, 190, 58),
    "Suzuki": (46, 110, 208),
    "Ducati": (200, 30, 42),
    "BMW": (40, 100, 190),
    "Harley-Davidson": (222, 108, 30),
    "Triumph": (176, 182, 196),
    "KTM": (232, 120, 26),
    "Aprilia": (200, 32, 48),
    "MV Agusta": (188, 32, 44),
    "Royal Enfield": (44, 92, 64),
    "Indian": (150, 32, 36),
    "Buell": (200, 44, 40),
    "Bimota": (200, 36, 44),
    "Norton": (86, 86, 96),
    "Husqvarna": (60, 120, 200),
    "CFMoto": (46, 110, 190),
    "QJMotor": (34, 34, 42),
    "Bajaj": (40, 90, 180),
    "TVS": (30, 80, 170),
    "Hero": (190, 40, 40),
    "Kymco": (60, 130, 190),
    "SYM": (200, 60, 50),
    "Zontes": (60, 110, 190),
    "Kove": (210, 60, 40),
    "Loncin": (60, 110, 190),
    "Rieju": (210, 50, 40),
    "GasGas": (200, 40, 40),
    "Horex": (180, 40, 40),
    "Kiden": (60, 110, 190),
    "Benda": (150, 60, 40),
    "LiveWire": (214, 218, 226),
    "BRP": (230, 150, 20),
    "BSA": (170, 40, 40),
    "Mahindra": (200, 50, 50),
}
FALLBACK = (190, 60, 50)


def load_specs() -> dict[str, float]:
    """asset -> real wheelbase in mm, from the bikez scrape."""
    import re as _re
    path = ROOT / "catalog" / "specs.csv"
    out: dict[str, float] = {}
    if not path.exists():
        return out
    with path.open() as handle:
        for row in csv.DictReader(handle):
            m = _re.search(r"([0-9]{3,4})\s*mm", row.get("Wheelbase", "") or "")
            if m:
                out[row["asset"]] = float(m.group(1))
    return out


SPECS = load_specs()


def oem_primary(brand: str, fallback):
    try:
        import livery as LV
        rgb = LV.primary(brand)
        return rgb or fallback
    except Exception:
        return fallback


def accent_for(primary: tuple[int, int, int]) -> tuple[int, int, int]:
    """A readable accent that contrasts with the body colour."""
    luminance = 0.299 * primary[0] + 0.587 * primary[1] + 0.114 * primary[2]
    return (24, 26, 32) if luminance > 150 else (238, 238, 242)


def load_template(name: str, width: int, colors: int) -> Image.Image:
    path = ASSETS / f"{name}.imageset" / f"{name}.png"
    return P.pixelate(Image.open(path), width=width, colors=colors)


def pick(pool: list[str], key: str) -> str:
    return pool[sum(ord(c) for c in key) % len(pool)]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--width", type=int, default=170)
    parser.add_argument("--colors", type=int, default=32)
    parser.add_argument("--scale", type=int, default=7)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--sheet", type=Path, default=ROOT / "pilot" / "generated-sheet.png")
    args = parser.parse_args()

    rows = list(csv.DictReader(PACK.open()))
    cache: dict[str, Image.Image] = {}

    families = F.load_families()
    lookup = F.build_lookup(families)

    def template(name: str) -> Image.Image:
        if name not in cache:
            cache[name] = load_template(name, args.width, args.colors)
        return cache[name]

    generated, skipped = [], {}
    from_ref = 0
    from_photo = 0
    for row in rows:
        photo = PHOTOS / f"{row['asset']}.png"
        if photo.exists():
            with Image.open(photo) as im:
                sprite = im.convert("RGBA")
            base = "photo"
            sprite.save(OUT / f"{row['asset']}.png")
            generated.append((row, base, sprite))
            from_photo += 1
            if args.limit and len(generated) >= args.limit:
                break
            continue
        family = lookup.get((row["brand"], row["model"])) or F.infer_family(
            row["brand"], row["model"], families
        )
        ref = F.reference_for(row["brand"], family) if family else None

        if ref is not None:
            key = f"ref:{ref}"
            if key not in cache:
                cache[key] = P.pixelate(Image.open(ref), width=args.width, colors=args.colors)
            base = f"ref:{ref.stem}"
            sprite = P.recolor(cache[key], BRAND_COLOURS.get(row["brand"], FALLBACK))
            from_ref += 1
        elif row["category"] in CLASS_3D:
            import render_models as RM

            kind = CLASS_3D[row["category"]]
            key = f"3d:{kind}:{row['brand']}:{row['model']}"
            if key not in cache:
                cache[key] = RM.sprite(kind, row["brand"].lower(), width=args.width,
                                       model=row["model"])
            base = f"3d:{kind}"
            sprite = cache[key]
        elif row["category"] in CLASS_PHOTO and Path(CLASS_PHOTO[row["category"]]).exists():
            photo = ROOT / CLASS_PHOTO[row["category"]]
            key = f"photo:{photo}"
            if key not in cache:
                cache[key] = P.pixelate(Image.open(photo), width=args.width, colors=args.colors, median=1)
            base = f"photo:{photo.stem}"
            sprite = P.recolor(cache[key], BRAND_COLOURS.get(row["brand"], FALLBACK))
        elif row["category"] in CLASS_ART:
            kind = CLASS_ART[row["category"]]
            colour = oem_primary(row["brand"], BRAND_COLOURS.get(row["brand"], FALLBACK))
            wheelbase = SPECS.get(row["asset"])
            key = f"class:{kind}:{row['brand']}:{wheelbase}"
            if key not in cache:
                livery = {"primary": colour, "accent": accent_for(colour)}
                fn = A.CLASSES[kind]
                try:
                    art = fn(livery, wheelbase_mm=wheelbase).to_image()
                except TypeError:
                    art = fn(livery).to_image()
                cache[key] = P.pixelate(art, width=args.width, colors=32, median=1)
            base = f"drawn:{kind}"
            sprite = cache[key]
        else:
            pool = TEMPLATES.get(row["category"])
            if not pool:
                skipped[row["category"]] = skipped.get(row["category"], 0) + 1
                continue
            base = pick(pool, row["asset"])
            sprite = P.recolor(template(base), BRAND_COLOURS.get(row["brand"], FALLBACK))

        generated.append((row, base, sprite))
        if args.limit and len(generated) >= args.limit:
            break

    print(f"{'asset':30} {'brand':16} {'category':12} template")
    for row, base, _ in generated:
        print(f"{row['asset']:30} {row['brand']:16} {row['category']:12} {base[5:]}")
    print(f"\ngenerated {len(generated)}" + (" (limited)" if args.limit else ""))
    print(f"  from catalogue photos  : {from_photo}")
    print(f"  from family references : {from_ref}")
    print(f"  from class templates   : {len(generated) - from_ref}")
    if not args.limit and skipped:
        print("skipped, no reference art for the class:")
        for category, count in sorted(skipped.items(), key=lambda kv: -kv[1]):
            print(f"  {category:14} {count:4}")

    if args.dry_run:
        return 0

    OUT.mkdir(parents=True, exist_ok=True)
    for row, _, sprite in generated:
        sprite.resize(
            (sprite.width * args.scale, sprite.height * args.scale), Image.NEAREST
        ).save(OUT / f"{row['asset']}.png")

    # Preview sheet
    if generated:
        picks = generated if len(generated) <= 12 else generated[:: max(1, len(generated) // 12)][:12]
        cell, label_h, margin = (300, 190), 26, 16
        columns = 4
        rows_n = (len(picks) + columns - 1) // columns
        sheet = Image.new(
            "RGB",
            (columns * cell[0] + margin, rows_n * (cell[1] + label_h) + margin),
            (10, 13, 20),
        )
        draw = ImageDraw.Draw(sheet)
        for index, (row, _, sprite) in enumerate(picks):
            column, line = index % columns, index // columns
            scale = min((cell[0] - 20) / sprite.width, (cell[1] - 16) / sprite.height)
            thumb = sprite.resize(
                (max(1, int(sprite.width * scale)), max(1, int(sprite.height * scale))),
                Image.NEAREST,
            )
            x = margin + column * cell[0] + (cell[0] - thumb.width) // 2
            y = margin + line * (cell[1] + label_h) + (cell[1] - thumb.height) // 2
            sheet.paste(thumb, (x, y), thumb)
            draw.text(
                (margin + column * cell[0] + 8, margin + line * (cell[1] + label_h) + cell[1] + 4),
                f"{row['brand']} {row['model']}"[:34],
                fill=(120, 132, 148),
            )
        sheet.save(args.sheet)
        print(f"sheet -> {args.sheet.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
