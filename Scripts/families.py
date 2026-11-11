#!/usr/bin/env python3
"""Map catalog models to the workbook's model families.

A family is the unit that actually looks alike: a Ninja ZX-6R and a ZX-10R
share a silhouette, a ZX-6R and a Vulcan 900 do not. The workbook already
groups every model into one of 70 families, so that table is the mapping used
to pick reference art.

Drop a side-profile render at ``bikes/refs/<brand>-<family>.jpeg`` and every
model in that family uses it. Without a reference the generator falls back to
a class template (sport / naked / touring), which is what it did before.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKBOOK = ROOT / "catalog" / "motorcycle_8bit_prompts.xlsx"
REFS = ROOT / "bikes" / "refs"


def slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def load_families() -> dict[tuple[str, str], list[str]]:
    """``(brand, family) -> [model, ...]`` from the prompt workbook."""
    import openpyxl

    wb = openpyxl.load_workbook(WORKBOOK, read_only=True)
    families: dict[tuple[str, str], list[str]] = {}
    for brand, _category, family, model, _years, _prompt in wb["Motorcycles"].iter_rows(
        min_row=2, values_only=True
    ):
        if not brand:
            continue
        key = (str(brand).strip(), str(family or model).strip())
        models = families.setdefault(key, [])
        if model and str(model) not in models:
            models.append(str(model))
    return families


def build_lookup(families: dict[tuple[str, str], list[str]]) -> dict[tuple[str, str], str]:
    """``(brand, model) -> family``."""
    lookup: dict[tuple[str, str], str] = {}
    for (brand, family), models in families.items():
        for model in models:
            lookup[(brand, model)] = family
    return lookup


def infer_family(brand: str, model: str, families: dict[tuple[str, str], list[str]]) -> str | None:
    """Best-effort family for a model the workbook does not list (legacy rows).

    Matches on the longest shared leading token, so "CBR929RR Fireblade" lands
    in the CBR family and "XL883 Iron" lands in Sportster via its model list.
    """
    candidates = [(b, f, models) for (b, f), models in families.items() if b == brand]
    if not candidates:
        return None

    words = model.split()
    head = re.sub(r"[^A-Z0-9]", "", words[0].upper()) if words else ""
    if head:
        for _b, family, models in candidates:
            if family.upper().startswith(head[:3]) and len(head) >= 2:
                return family
            for known in models:
                known_head = re.sub(r"[^A-Z0-9]", "", known.split()[0].upper())
                if known_head and known_head == head:
                    return family

    for _b, family, models in candidates:
        for known in models:
            if known.lower() in model.lower() or model.lower() in known.lower():
                return family
    return None


def reference_for(brand: str, family: str) -> Path | None:
    """Existing side-profile reference for a family, if one has been dropped in."""
    base = REFS / f"{slug(brand)}-{slug(family)}"
    for suffix in (".jpeg", ".jpg", ".png"):
        path = base.with_suffix(suffix)
        if path.exists():
            return path
    return None


def reference_index() -> dict[tuple[str, str], Path]:
    found = {}
    if not REFS.exists():
        return found
    for path in REFS.iterdir():
        if path.suffix.lower() in {".jpeg", ".jpg", ".png"}:
            found[(slug(path.stem),)] = path
    return found
