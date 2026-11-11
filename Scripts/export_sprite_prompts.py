#!/usr/bin/env python3
"""Export a ready-to-use image-generation pack for the bikes without sprites.

The catalog has far more models than the hand-finished art set. This script
reads the prompt workbook (the source of truth for brand/model/category/style),
works out which catalog entries still have no artwork, and writes one row per
missing sprite with a finished prompt and the exact filename the importer
expects.

Drop the renders into ``bikes/`` under the ``filename`` column, run
``Scripts/import_bike_sprites.py``, and the asset catalog picks them up.

Usage:
    python3 Scripts/export_sprite_prompts.py                 # -> catalog/sprite-prompts.csv
    python3 Scripts/export_sprite_prompts.py --limit 5       # sample
    python3 Scripts/export_sprite_prompts.py --include-covered
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKBOOK = ROOT / "catalog" / "motorcycle_8bit_prompts.xlsx"
CATALOG_SWIFT = ROOT / "revert" / "BikeCatalogData.swift"
SPRITES_SWIFT = ROOT / "revert" / "BikeSprites.swift"
ASSET_DIR = ROOT / "revert" / "BikeSprites.xcassets"
OUT = ROOT / "catalog" / "sprite-prompts.csv"

DEFAULT_STYLE = (
    "retro NES-style 16-color palette, chunky clean pixels, "
    "plain solid background, no rider, game-ready sprite"
)


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def catalog_entries() -> list[dict]:
    entries = []
    for line in CATALOG_SWIFT.read_text().splitlines():
        parts = line.strip().split("|")
        if len(parts) != 4 or line.strip().startswith("//"):
            continue
        brand, model, years, category = parts
        entries.append(
            {"brand": brand, "model": model, "years": years,
             "category": category, "uuid": "|".join(parts)}
        )
    return entries


def covered_models() -> set[str]:
    text = SPRITES_SWIFT.read_text().split("families", 1)[1]
    return set(re.findall(r'"(Honda [^"]+)"', text))


def workbook_rows() -> tuple[list[dict], str]:
    import openpyxl

    wb = openpyxl.load_workbook(WORKBOOK)
    style = DEFAULT_STYLE
    if "Style" in wb.sheetnames:
        for row in wb["Style"].iter_rows(values_only=True):
            if row and str(row[0]).strip().lower() == "style text" and row[1]:
                style = str(row[1]).strip()

    rows = []
    ws = wb["Motorcycles"]
    header = [c.value for c in ws[1]]
    for values in ws.iter_rows(min_row=2, values_only=True):
        if not values or not values[0]:
            continue
        record = dict(zip(header, values))
        rows.append(record)
    return rows, style


def prompt_for(brand: str, model: str, category: str, style: str) -> str:
    return (
        f"8-bit pixel art sprite of a {brand} {model} {category.lower()} motorcycle, "
        f"side profile facing right, {style}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--include-covered", action="store_true")
    args = parser.parse_args()

    _, style = workbook_rows()
    entries = catalog_entries()
    covered = covered_models()
    existing_assets = {p.stem for p in ASSET_DIR.glob("*.imageset")}

    used: dict[str, str] = {}
    rows = []
    for entry in entries:
        name = f"{entry['brand']} {entry['model']} {entry['years']}".strip()
        name = re.sub(r"\s+", " ", name)
        if not args.include_covered and name in covered:
            continue

        base = slug(entry["model"])
        candidates = [
            f"bike-{base}",
            f"bike-{base}-{slug(entry['years'])}",
            f"bike-{base}-{slug(entry['brand'])}",
            f"bike-{base}-{slug(entry['brand'])}-{slug(entry['years'])}",
        ]
        asset = next(
            (c for c in candidates if used.get(c) in (None, name) and c not in existing_assets),
            None,
        )
        if asset is None:  # exhaustive fallback, keep it deterministic
            suffix = 2
            while f"bike-{base}-{suffix}" in used:
                suffix += 1
            asset = f"bike-{base}-{suffix}"
        used[asset] = name

        rows.append(
            {
                "filename": f"{asset[len('bike-'):]}.jpeg",
                "asset": asset,
                "brand": entry["brand"],
                "model": entry["model"],
                "years": entry["years"],
                "category": entry["category"],
                "prompt": prompt_for(entry["brand"], entry["model"], entry["category"], style),
            }
        )

    rows.sort(key=lambda r: (r["brand"], r["model"], r["years"]))
    if args.limit:
        rows = rows[: args.limit]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"{len(rows)} missing sprites -> {args.out.relative_to(ROOT)}")
    print(f"style: {style[:64]}...")
    if rows:
        print("\nsample row:")
        for key, value in rows[0].items():
            print(f"  {key:9} {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
