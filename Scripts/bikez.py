#!/usr/bin/env python3
"""Scrape real specifications from bikez.com.

Bikez carries a spec table for ~40,000 motorcycles: wheelbase, seat height,
weight, rake, trail, displacement. That's the dimensions data the art pipeline
has been missing - until now proportions came from measuring photos.

Builds a per-brand slug index (the brand pages paginate), matches catalog
models to slugs, then pulls and parses each spec page.

Usage:
    python3 Scripts/bikez.py --brand honda --limit 40
    python3 Scripts/bikez.py --all --out catalog/specs.csv
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "catalog" / "specs.csv"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"
BASE = "https://bikez.com"

FIELDS = ("Wheelbase", "Seat height", "Dry weight", "Weight", "Rake", "Trail",
          "Displacement", "Power", "Torque", "Fuel capacity")


def get(url: str, attempts: int = 3) -> str:
    for i in range(attempts):
        raw = subprocess.run(["curl", "-sSL", "--max-time", "30", "-A", UA, url],
                             capture_output=True).stdout
        # bikez serves some pages in Latin-1; never let a decode error kill the run
        out = raw.decode("utf-8", errors="replace") if raw else ""
        if out and "Motorcycle catalog" not in out[:2000]:
            return out
        if out and "<title>" in out:
            return out
        time.sleep(1.5 * (i + 1))
    return ""


def brand_slugs(make: str, max_pages: int = 20) -> list[str]:
    """Every model slug on a brand page, following its pagination."""
    slugs: set[str] = set()
    pattern = re.compile(rf"/motorcycles/{re.escape(make.lower())}_[a-z0-9_\-]+\.php")
    for page in range(1, max_pages + 1):
        url = f"{BASE}/brand/{make.lower()}_motorcycles.php?sort=year"
        if page > 1:
            url += f"&page={page}"
        html = get(url)
        found = set(pattern.findall(html))
        new = found - slugs
        slugs |= found
        if not new or not found:
            break
        time.sleep(0.4)
    return sorted(s.replace("/motorcycles/", "").replace(".php", "") for s in slugs)


def parse_specs(html: str) -> dict:
    """Read the spec table generically: label cell, value cell.

    Labels are sometimes linked (Wheelbase) and sometimes plain (Seat height),
    so matching on tag shape alone misses half the table.
    """
    out = {}
    for row in re.findall(r"<tr>(.*?)</tr>", html, re.S):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row, re.S)
        if len(cells) != 2:
            continue
        label = re.sub(r"<[^>]+>", "", cells[0]).strip().rstrip(":")
        value = re.sub(r"<[^>]+>", " ", cells[1])
        value = re.sub(r"\s+", " ", value).strip()
        if label and value and label in FIELDS:
            out[label] = value[:48]
    return out


def fetch_specs(slug: str) -> dict:
    html = get(f"{BASE}/motorcycles/{slug}.php")
    title = re.search(r"<title>([^<]+)", html)
    picture = re.search(r'src="(https://bikez\.com/pictures/[^"]+)"', html)
    return {"slug": slug, "title": title.group(1).strip() if title else "",
            "picture": picture.group(1) if picture else "", **parse_specs(html)}


def normalise(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def match(model: str, slugs: list[str]) -> str | None:
    """Find the slug whose non-year part best matches the catalog model."""
    target = normalise(model)
    best, best_score = None, 0.0
    for slug in slugs:
        parts = slug.rsplit("_", 1)
        if len(parts) != 2 or not parts[1].isdigit():
            continue
        stem = normalise(parts[0].split("_", 1)[-1])
        if stem == target:
            return slug
        if target.startswith(stem) or stem.startswith(target):
            # a catalog name often carries trim words ("CBR1000RR Fireblade"),
            # so score on the shared prefix rather than whole-string equality
            score = min(len(stem), len(target)) / max(len(stem), len(target))
            if score > best_score:
                best, best_score = slug, score
    return best if best_score >= 0.5 else None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brand", type=str)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    rows = list(csv.DictReader((ROOT / "catalog" / "sprite-prompts.csv").open()))
    brands = ([args.brand] if args.brand else
              sorted({r["brand"] for r in rows}) if args.all else [])
    if not brands:
        parser.print_help()
        return 0

    results, matched = [], 0
    for brand in brands:
        slugs = brand_slugs(brand)
        print(f"{brand}: {len(slugs)} model slugs indexed", flush=True)
        targets = [r for r in rows if r["brand"].lower() == brand.lower()]
        if args.limit:
            targets = targets[: args.limit]
        for row in targets:
            slug = match(row["model"], slugs)
            if not slug:
                continue
            specs = fetch_specs(slug)
            if not specs.get("Wheelbase"):
                continue
            matched += 1
            results.append({"asset": row["asset"], "brand": brand, "model": row["model"],
                            "catalog_years": row["years"], "slug": slug,
                            "picture": specs.get("picture", ""),
                            **{k: specs.get(k, "") for k in ("title", *FIELDS)}})
            if matched % 10 == 0:
                print(f"  {matched} matched…", flush=True)
            time.sleep(0.3)

    if results:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        with args.out.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(results[0].keys()))
            writer.writeheader()
            writer.writerows(results)
        print(f"\n{matched} bikes with specs -> {args.out.relative_to(ROOT)}")
        with_wb = sum(1 for r in results if r.get("Wheelbase"))
        print(f"wheelbase present: {with_wb}")
    else:
        print("no specs matched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
