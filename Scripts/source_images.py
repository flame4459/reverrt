#!/usr/bin/env python3
"""Find and download high-resolution side-view source images per bike.

Bing Images is used instead of Google Images because it exposes direct image
URLs in the result HTML; the query set is the same. Everything lands under
``pilot/sources/<asset>/`` (git-ignored) with a manifest, so the material can be
reviewed locally without being redistributed.

Usage:
    python3 Scripts/source_images.py --assets bike-1098 bike-cb1000r
    python3 Scripts/source_images.py --limit 20 --per-query 6
    python3 Scripts/source_images.py --all --resume
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import random
import re
import subprocess
import time
from pathlib import Path

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PACK = ROOT / "catalog" / "sprite-prompts.csv"
OUT = ROOT / "pilot" / "sources"
MANIFEST = OUT / "manifest.csv"

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36")
HEADERS = {
    "User-Agent": UA,
    "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.bing.com/",
}

QUERIES = [
    "{brand} {model} motorcycle side view",
    "{brand} {model} side profile studio",
    "{brand} {model} {years} side elevation",
]

MURL = re.compile(r'murl&quot;:&quot;(.*?)&quot;', re.S)


def load_rows() -> list[dict]:
    with PACK.open() as handle:
        return list(csv.DictReader(handle))


def bing_urls(query: str, count: int = 35) -> list[str]:
    url = "https://www.bing.com/images/search"
    params = {"q": query, "first": 1, "count": count, "form": "HDRSC2"}
    response = requests.get(url, params=params, headers={"User-Agent": UA}, timeout=25)
    response.raise_for_status()
    found = []
    for raw in MURL.findall(response.text):
        candidate = html.unescape(raw)
        if candidate.startswith("http") and candidate not in found:
            found.append(candidate)
    return found


def download(url: str, destination: Path, session: requests.Session) -> tuple[bool, str]:
    try:
        response = session.get(url, headers=HEADERS, timeout=25, stream=True)
        response.raise_for_status()
        data = response.content
        if len(data) < 20_000:
            return False, "too small"
        try:
            image = Image.open(io.BytesIO(data))
            image.load()
        except Exception:
            # AVIF/WebP that Pillow cannot decode: let macOS convert it.
            raw = destination.with_suffix(".raw")
            raw.write_bytes(data)
            result = subprocess.run(
                ["sips", "-s", "format", "jpeg", str(raw), "--out", str(destination)],
                capture_output=True, timeout=30)
            raw.unlink(missing_ok=True)
            if result.returncode != 0 or not destination.exists():
                return False, "undecodable image"
            image = Image.open(destination)
            image.load()
        if image.width < 900 or image.height < 500:
            return False, f"small {image.width}x{image.height}"
        aspect = image.width / max(image.height, 1)
        if not (1.05 <= aspect <= 3.3):
            return False, f"aspect {aspect:.2f}"
        image = image.convert("RGB")
        image.save(destination, "JPEG", quality=92, optimize=True)
        return True, f"{image.width}x{image.height}"
    except Exception as exc:
        return False, str(exc)[:80]


def run(assets: list[str], per_query: int, queries: list[str], resume: bool) -> int:
    rows = {row["asset"]: row for row in load_rows()}
    OUT.mkdir(parents=True, exist_ok=True)
    session = requests.Session()

    manifest_exists = MANIFEST.exists()
    handle = MANIFEST.open("a", newline="")
    writer = csv.DictWriter(handle, fieldnames=[
        "asset", "brand", "model", "query", "rank", "url", "path",
        "ok", "detail", "bytes",
    ])
    if not manifest_exists:
        writer.writeheader()

    for asset in assets:
        row = rows.get(asset)
        if row is None:
            print(f"skip {asset}: not in catalogue")
            continue
        folder = OUT / asset
        folder.mkdir(parents=True, exist_ok=True)
        existing = list(folder.glob("*.jpg"))
        if resume and len(existing) >= per_query * len(queries):
            print(f"{asset}: {len(existing)} already, skip")
            continue

        rank = 0
        for template in queries:
            query = template.format(brand=row["brand"], model=row["model"],
                                    years=row.get("years", ""))
            try:
                urls = bing_urls(query)
            except Exception as exc:
                print(f"  search failed: {query}: {exc}")
                continue
            print(f"{asset}: {query} -> {len(urls)} urls")
            for url in urls:
                if rank >= per_query * len(queries):
                    break
                rank += 1
                destination = folder / f"{rank:02d}.jpg"
                if destination.exists():
                    continue
                ok, detail = download(url, destination, session)
                if not ok:
                    destination.unlink(missing_ok=True)
                writer.writerow({
                    "asset": asset, "brand": row["brand"], "model": row["model"],
                    "query": query, "rank": rank, "url": url,
                    "path": str(destination.relative_to(ROOT)),
                    "ok": int(ok), "detail": detail,
                    "bytes": destination.stat().st_size if destination.exists() else 0,
                })
                handle.flush()
                print(f"  {rank:02d} {'ok ' if ok else 'no '} {detail}")
                time.sleep(random.uniform(0.6, 1.4))
            time.sleep(random.uniform(1.0, 2.0))

    handle.close()
    good = sum(1 for p in OUT.glob("*/*.jpg"))
    print(f"\n{good} candidate images under {OUT.relative_to(ROOT)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", nargs="*")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--per-query", type=int, default=3)
    parser.add_argument("--queries", type=int, default=3)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    rows = load_rows()
    if args.assets:
        assets = args.assets
    elif args.all:
        assets = [row["asset"] for row in rows]
    else:
        assets = [row["asset"] for row in rows[: args.limit or 5]]
    return run(assets, args.per_query, QUERIES[: args.queries], args.resume)


if __name__ == "__main__":
    raise SystemExit(main())
