#!/usr/bin/env python3
"""Workbench for the 70 family reference renders.

The catalogue is grouped into 70 families. One finished side elevation per
family is re-liveried into every model in that family, so 70 renders replace
the ~1,000 hand-drawn placeholders. Three references exist (Honda); this lists
the rest, validates what is there, and writes a prompt pack for the gap.

Usage:
    python3 Scripts/family_refs.py report
    python3 Scripts/family_refs.py pack
    python3 Scripts/family_refs.py report --verbose
"""

from __future__ import annotations

import argparse
import csv
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

WISHLIST = ROOT / "catalog" / "reference-wishlist.csv"
REFS = ROOT / "bikes" / "refs"
PACK_MD = ROOT / "catalog" / "family-reference-pack.md"
PACK_CSV = ROOT / "catalog" / "family-reference-prompts.csv"


def load_rows() -> list[dict]:
    with WISHLIST.open() as handle:
        return list(csv.DictReader(handle))


def target_path(row: dict) -> Path:
    """The file the wishlist asks for, preferring an existing extension."""
    wanted = ROOT / row["ref_filename"]
    base = wanted.with_suffix("")
    for suffix in (wanted.suffix, ".jpeg", ".jpg", ".png"):
        candidate = Path(str(base) + suffix)
        if candidate.exists():
            return candidate
    return wanted


def audit(path: Path) -> dict:
    from check_references import audit as reference_audit

    try:
        return reference_audit(path)
    except Exception as exc:  # unreadable / corrupt image
        return {"ok": False, "why": f"cannot read: {exc}"}


def status() -> tuple[list, list, list]:
    ready, broken, missing = [], [], []
    for row in load_rows():
        path = target_path(row)
        if not path.exists():
            missing.append((row, path))
            continue
        info = audit(path)
        (ready if info.get("ok") else broken).append((row, path, info))
    return ready, broken, missing


def report(verbose: bool) -> int:
    ready, broken, missing = status()
    total = len(ready) + len(broken) + len(missing)
    covered = sum(int(r["models_covered"]) for r, _, _ in ready)
    missing_models = sum(int(r["models_covered"]) for r, _ in missing)

    print(f"families: {total}   ready: {len(ready)}   needs work: {len(broken)}   missing: {len(missing)}")
    print(f"models covered by ready refs: {covered}   by missing refs: {missing_models}\n")

    print("READY")
    for row, path, info in sorted(ready, key=lambda x: -int(x[0]["models_covered"])):
        print(f"  {row['brand']:16} {row['family']:22} {row['models_covered']:>3} models  "
              f"{info.get('size',''):>10}  {path.relative_to(ROOT)}")

    if broken:
        print("\nNEEDS WORK")
        for row, path, info in sorted(broken, key=lambda x: -int(x[0]["models_covered"])):
            print(f"  {row['brand']:16} {row['family']:22} {row['models_covered']:>3} models  "
                  f"{info.get('why','')}")

    if missing:
        print("\nMISSING BY BRAND")
        brands = Counter(row["brand"] for row, _ in missing)
        for brand, count in brands.most_common():
            models = sum(int(row["models_covered"]) for row, _ in missing if row["brand"] == brand)
            print(f"  {brand:16} {count:2} families  {models:3} models")

    if verbose and missing:
        print("\nMISSING")
        for row, path in sorted(missing, key=lambda x: -int(x[0]["models_covered"])):
            print(f"  {row['brand']:16} {row['family']:22} {row['models_covered']:>3} models  "
                  f"-> {path.relative_to(ROOT)}")

    print(f"\nprompt pack: {PACK_MD.relative_to(ROOT)}  (run: family_refs.py pack)")
    return 0


def pack() -> int:
    ready, broken, missing = status()
    rows = load_rows()

    PACK_CSV.parent.mkdir(parents=True, exist_ok=True)
    with PACK_CSV.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=[
            "ref_filename", "brand", "family", "models_covered",
            "example_models", "prompt", "target", "status",
        ], extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            path = target_path(row)
            status_text = "have" if path.exists() else "missing"
            writer.writerow({**row, "status": status_text})

    lines = [
        "# Family reference pack",
        "",
        "One finished side elevation per family replaces every placeholder in that family.",
        f"{len(ready)} ready, {len(broken)} need work, {len(missing)} missing.",
        "",
        "Target: ~1200 x 800, side elevation, full bike, both wheels down, front wheel",
        "to the right, plain background, no rider, no text, no watermark, no floor shadow.",
        "Save exactly as the `ref_filename` below, then:",
        "",
        "```sh",
        "python3 Scripts/check_references.py      # validate (needs openpyxl)",
        "python3 Scripts/family_refs.py report    # same, without the workbook",
        "python3 Scripts/generate_bike_sprites.py --width 170 --scale 7",
        "python3 Scripts/import_bike_sprites.py",
        "```",
        "",
        "The prompt in the wishlist is written for a text-to-image model. Generate",
        "several candidates, pick the cleanest side elevation, and keep the bike's",
        "actual livery; a generic fantasy bike is worse than the placeholder.",
        "",
        "## Missing",
        "",
    ]

    for row, path in sorted(missing, key=lambda r: (r[0]["brand"], -int(r[0]["models_covered"]))):
        lines += [
            f"### {row['brand']} — {row['family']}  ({row['models_covered']} models)  ",
            f"`{row['ref_filename']}`",
            "",
            f"Examples: {row['example_models']}",
            "",
            f"> {row['prompt']}",
            "",
        ]

    if broken:
        lines += ["## Need work", ""]
        for row, path, info in broken:
            lines += [
                f"### {row['brand']} — {row['family']}  ({row['models_covered']} models)",
                f"`{path.relative_to(ROOT)}` — {info.get('why', '')}",
                "",
            ]

    PACK_MD.write_text("\n".join(lines))
    print(f"{len(missing)} missing, {len(broken)} need work")
    print(f"-> {PACK_MD.relative_to(ROOT)}")
    print(f"-> {PACK_CSV.relative_to(ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="report", choices=["report", "pack"])
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    return report(args.verbose) if args.command == "report" else pack()


if __name__ == "__main__":
    raise SystemExit(main())
