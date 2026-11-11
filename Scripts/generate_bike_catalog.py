#!/usr/bin/env python3
"""Build ``BikeCatalogData.swift`` from the prompt workbook plus the legacy list.

The picker's model list has two sources:

* ``catalog/motorcycle_8bit_prompts.xlsx`` — the master list of models that get
  a pixel-art sprite, with brand, category, model and approximate year range.
* ``catalog/legacy_bikes.txt`` — the hand-curated entries that predate the
  workbook (and are already wired to finished sprites). These stay, so a bike
  the user already selected keeps its name and artwork.

The merge is additive: a workbook row is only appended when no legacy entry
already covers that model. Rows are written one per line as
``Brand|Model|Years|Category`` and parsed once at launch by ``BikeCatalog``.

Usage:
    python3 Scripts/generate_bike_catalog.py            # write Swift data
    python3 Scripts/generate_bike_catalog.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parent.parent
WORKBOOK = ROOT / "catalog" / "motorcycle_8bit_prompts.xlsx"
LEGACY = ROOT / "catalog" / "legacy_bikes.txt"
OUTPUT = ROOT / "revert" / "BikeCatalogData.swift"
VIABILITY = ROOT / "catalog" / "brand-viability.csv"

# Longest first so "Royal Enfield" wins over a hypothetical "Royal".
BRANDS = [
    "Harley-Davidson", "Royal Enfield", "MV Agusta", "LiveWire", "BRP", "CFMoto",
    "QJMotor", "Kymco", "SYM", "TVS", "Bajaj", "Hero", "Buell", "Norton", "Rieju",
    "Horex", "BSA", "GasGas", "Zontes", "Kiden", "Loncin", "Benda", "Mahindra",
    "Kove", "Bimota", "Husqvarna", "Aprilia", "Ducati", "Triumph", "Suzuki",
    "Kawasaki", "Yamaha", "Honda", "KTM", "BMW", "Indian",
]

# Workbook vocabulary -> BikeCategory cases in the app.
CATEGORIES = {
    "Sportbike": "Sportbike",
    "Naked": "Naked",
    "Cruiser": "Cruiser",
    "Adventure": "Adventure",
    "Touring": "Touring",
    "Standard/Retro": "Standard",
    "Dual-sport": "Dual-sport",
    "Scooter": "Scooter",
    "Mini/Small": "Mini",
    "Supermoto": "Supermoto",
    "Trike": "Trike",
}

# The workbook files a category per *family*, so a family that spans body styles
# mislabels its outliers. These are models where the family label is clearly
# wrong; category drives which silhouette the sprite borrows.
CATEGORY_OVERRIDES = {
    ("Aprilia", "Mana 850"): "Naked",
    ("Aprilia", "SL 750 Shiver GT"): "Naked",
    ("Triumph", "Trophy 900"): "Touring",
    ("Triumph", "Trophy 1200"): "Touring",
    ("Triumph", "Trophy 1215"): "Touring",
    ("Kawasaki", "Vulcan 1700 Voyager"): "Touring",
    ("Suzuki", "Hayabusa"): "Sportbike",
}

# Legacy entries are overwhelmingly sport bikes; these are the exceptions.
LEGACY_TOURING = [
    "VFR750F", "VFR800", "VFR1200F", "CBR1000F", "CBR1100XX", "Hayabusa",
    "ZX-14R", "ZZR600",
]
LEGACY_NAKED = [
    "CB1000R", "CB125R", "CB300R", "CB600F", "CB900F", "Monster", "Streetfighter",
    "Tuono", "Brutale", "S1000R", "M 1000 R", "F 900 R", "GSX-S1000", "Vitpilen",
    "Trident", "Street Triple", "Speed Triple", "450NK", "800NK", "XR1200",
    "LiveWire", "Continental GT", "961 Sport",
]
LEGACY_ADVENTURE = ["Niken"]

# Words that describe a trim rather than the model itself, dropped before the
# workbook is compared with the legacy list.
NOISE = {"fireblade", "blackbird", "hurricane", "superhawk", "interceptor", "dct", "e-clutch", "abs"}

# Model-level aliases where the workbook spells a name differently to the
# legacy list in a way token matching cannot see.
ALIASES: dict[tuple[str, str], tuple[str, ...]] = {}


def load_keep_list() -> set[str]:
    """Brands worth keeping: anything with realistic ownership odds in the US/EU."""
    import csv

    if not VIABILITY.exists():
        return set()
    with VIABILITY.open() as handle:
        return {
            row["brand"].strip()
            for row in csv.DictReader(handle)
            if row["keep"].strip().lower() in {"yes", "true", "1"}
        }


def split_legacy(name: str) -> tuple[str, str, str]:
    """``Honda CBR900RR Fireblade 1994`` -> ``("Honda", "CBR900RR Fireblade", "1994")``."""
    for brand in BRANDS:
        if name.startswith(brand + " "):
            rest = name[len(brand) + 1 :].strip()
            break
    else:
        raise SystemExit(f"legacy entry has no known brand: {name!r}")

    years = ""
    match = re.search(r"\s(19|20)\d{2}$", rest)
    if match:
        years = rest[match.start() + 1 :]
        rest = rest[: match.start()].strip()
    return brand, rest, years


def normalize(text: str) -> tuple[str, ...]:
    lowered = text.lower().replace("&", " and ")
    lowered = re.sub(r"[^a-z0-9]+", " ", lowered)
    return tuple(token for token in lowered.split() if token not in NOISE)


def squash(tokens: tuple[str, ...]) -> str:
    return "".join(tokens)


def covers(legacy: tuple[str, ...], candidate: tuple[str, ...]) -> bool:
    """True when both names describe the same model.

    Manufacturers disagree about spacing ("S1000RR" / "S 1000 RR"), so compare
    the joined tokens first, then allow one name to be a token-prefix of the
    other ("CB600F Hornet" / "CB600F Hornet 599").
    """
    if legacy == candidate or squash(legacy) == squash(candidate):
        return True
    shorter, longer = sorted((legacy, candidate), key=len)
    if not shorter or longer[: len(shorter)] != shorter:
        return False
    # A trailing engine size marks a different model (Monster 400 vs Monster),
    # while trailing trim words are the same machine in another spec.
    extra = longer[len(shorter)]
    return not extra[:1].isdigit()


def best_legacy_match(brand: str, key: tuple[str, ...], legacy_keys: dict) -> str | None:
    best = None
    for (legacy_brand, legacy_key), name in legacy_keys.items():
        if legacy_brand != brand.lower() or not covers(legacy_key, key):
            continue
        score = len(legacy_key)
        if best is None or score > best[0]:
            best = (score, name)
    return best[1] if best else None


def legacy_category(brand: str, model: str) -> str:
    for prefix in LEGACY_TOURING:
        if model.startswith(prefix):
            return "Touring"
    for prefix in LEGACY_NAKED:
        if model.startswith(prefix):
            return "Naked"
    for prefix in LEGACY_ADVENTURE:
        if model.startswith(prefix):
            return "Adventure"
    return "Sportbike"


def natural_key(text: str):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", text.lower())]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    keep = load_keep_list()
    dropped: dict[str, int] = {}

    legacy_rows = []
    legacy_keys = {}
    for line in LEGACY.read_text().splitlines():
        name = line.strip()
        if not name:
            continue
        brand, model, years = split_legacy(name)
        rebuilt = " ".join(part for part in (brand, model, years) if part)
        if rebuilt != name:
            raise SystemExit(f"legacy round-trip failed: {name!r} -> {rebuilt!r}")
        if keep and brand not in keep:
            dropped[brand] = dropped.get(brand, 0) + 1
            continue
        category = legacy_category(brand, model)
        legacy_rows.append((brand, model, years, category))
        legacy_keys[(brand.lower(), normalize(model))] = name

    workbook = load_workbook(WORKBOOK, data_only=True)
    sheet = workbook["Motorcycles"]
    added, skipped = [], []

    for row in sheet.iter_rows(min_row=2, values_only=True):
        brand, category, _family, model, years = row[0], row[1], row[2], row[3], row[4]
        if not brand or not model:
            continue
        if keep and str(brand).strip() not in keep:
            dropped[str(brand)] = dropped.get(str(brand), 0) + 1
            continue
        category = CATEGORIES.get(str(category).strip())
        if category is None:
            raise SystemExit(f"unknown category {row[1]!r} for {brand} {model}")

        key = normalize(str(model))
        alias = ALIASES.get((str(brand).lower(), " ".join(key)))
        match = best_legacy_match(str(brand), key, legacy_keys)
        if match is None and alias:
            match = best_legacy_match(str(brand), alias, legacy_keys)

        if match:
            skipped.append((f"{brand} {model} {years}", match))
            continue
        override = CATEGORY_OVERRIDES.get((str(brand), str(model).strip()))
        if override:
            category = override
        added.append((str(brand), str(model).strip(), str(years).strip(), category))

    merged = legacy_rows + added
    merged.sort(key=lambda r: (r[0], natural_key(r[1]), natural_key(r[2])))

    lines = [f"{brand}|{model}|{years}|{category}" for brand, model, years, category in merged]
    payload = "\n".join(lines)

    print(f"legacy: {len(legacy_rows)}  added: {len(added)}  skipped as duplicates: {len(skipped)}")
    if dropped:
        print(f"pruned brands with near-zero ownership odds: {sum(dropped.values())} models")
        for brand, count in sorted(dropped.items(), key=lambda kv: -kv[1]):
            print(f"  drop {brand:18} {count:4}")
    print(f"total: {len(merged)}")
    for name, legacy_name in skipped:
        print(f"  skip {name:46} (covered by {legacy_name})")

    if args.dry_run:
        return 0

    OUTPUT.write_text(
        "// Generated by Scripts/generate_bike_catalog.py — do not edit by hand.\n"
        "// Format: Brand|Model|Years|Category\n"
        "enum BikeCatalogData {\n"
        '    static let entries = """\n'
        f"{payload}\n"
        '"""\n'
        "}\n"
    )
    print(f"wrote {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
