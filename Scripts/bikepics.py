#!/usr/bin/env python3
"""Pull per-model reference photos from BikePics.

BikePics indexes 2M+ owner photos by make and model, which is exactly the
per-model reference we've been missing. This module resolves a catalog model to
a BikePics model page (via the manufacturer's model list, not by guessing slugs),
lists that page's photos and downloads a handful for the cut-out pipeline.

Usage:
    python3 Scripts/bikepics.py --list kawasaki
    python3 Scripts/bikepics.py --fetch "Kawasaki ZX-6R" --limit 6
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "refs" / "bikepics"
UA = "RevertSpriteRefs/1.0 (personal art reference; contact rider-app@example.com)"
BASE = "https://bikepics.com"

_CACHE: dict[str, list[tuple[str, str]]] = {}


def _get(url: str, binary: bool = False):
    for attempt in range(3):
        result = subprocess.run(
            ["curl", "-sS", "--max-time", "30", "-A", UA, url],
            capture_output=True, text=(not binary),
        )
        if result.returncode == 0:
            return result.stdout
        time.sleep(1.5 * (attempt + 1))
    return None


def models_for(make: str) -> list[tuple[str, str]]:
    """[(slug, display name)] from the manufacturer page."""
    key = make.lower()
    if key in _CACHE:
        return _CACHE[key]
    html = _get(f"{BASE}/manufacturers/{key}")
    found = {}
    if html:
        for slug, name in re.findall(
            rf'/manufacturers/{re.escape(key)}/models/([a-z0-9\-]+)"[^>]*>([^<]+)<', html
        ):
            found[slug] = name.strip()
    _CACHE[key] = sorted(found.items())
    return _CACHE[key]


def normalise(text: str) -> str:
    return re.sub(r"[^a-z0-9]", "", text.lower())


def resolve(make: str, model: str) -> str | None:
    """Best BikePics slug for a catalog model."""
    target = normalise(model)
    best, best_score = None, 0.0
    for slug, name in models_for(make):
        candidate = normalise(name)
        if candidate == target or normalise(slug) == target:
            return slug
        if not candidate:
            continue
        if target.startswith(candidate) or candidate.startswith(target):
            score = min(len(candidate), len(target)) / max(len(candidate), len(target))
            if score > best_score:
                best, best_score = slug, score
    return best if best_score >= 0.6 else None


def photo_urls(slug: str, make: str, limit: int = 8) -> list[str]:
    html = _get(f"{BASE}/manufacturers/{make.lower()}/models/{slug}")
    if not html:
        return []
    ids = re.findall(r'posts/(\d+)\.jpg', html)
    seen, out = set(), []
    for pid in ids:
        if pid in seen:
            continue
        seen.add(pid)
        out.append(f"https://user-content.bikepics.com/posts/{pid}.jpg")
        if len(out) >= limit:
            break
    return out


def fetch(make: str, model: str, limit: int = 6) -> list[Path]:
    slug = resolve(make, model)
    if not slug:
        print(f"  no BikePics model for {make} {model}")
        return []
    folder = OUT / f"{make.lower()}-{slug}"
    folder.mkdir(parents=True, exist_ok=True)
    saved = []
    for i, url in enumerate(photo_urls(slug, make, limit)):
        path = folder / f"p{i:02d}.jpg"
        if path.exists():
            saved.append(path)
            continue
        data = _get(url, binary=True)
        if not data:
            continue
        path.write_bytes(data)
        saved.append(path)
        time.sleep(0.3)
    print(f"  {make} {model} -> {slug}: {len(saved)} photos in {folder.name}")
    return saved


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", type=str, help="list models for a make")
    parser.add_argument("--fetch", type=str, help='"Make Model" to download')
    parser.add_argument("--limit", type=int, default=6)
    args = parser.parse_args()

    if args.list:
        for slug, name in models_for(args.list)[:60]:
            print(f"  {slug:24} {name}")
        print(f"{len(models_for(args.list))} models")
        return 0

    if args.fetch:
        make, _, model = args.fetch.partition(" ")
        fetch(make, model, args.limit)
        return 0

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
