#!/usr/bin/env python3
"""Source real-world reference photos for every bike family.

Sprites are shared per family, so references are too: one clean side profile per
family covers every model in it. This script searches Wikimedia Commons for each
family, downloads candidates, scores them on how useful they'd be to draw
against (side-on framing, plain background, subject fills the frame) and writes a
review sheet plus a manifest.

Images are kept as *drawing references only* - they are never shipped. Licence
and author metadata is recorded in the manifest for attribution if needed.

Usage:
    python3 Scripts/source_references.py                 # all families
    python3 Scripts/source_references.py --only kawasaki --limit-families 5
    python3 Scripts/source_references.py --per-family 3
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import time
import urllib.parse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "Scripts"))

import families as F  # noqa: E402

OUT = ROOT / "refs"
API = "https://commons.wikimedia.org/w/api.php"
UA = "RevertSpriteRefs/1.0 (personal motorcycle art project; contact: rider-app@example.com)"
MIN_INTERVAL = 1.4  # Wikimedia asks for at most one request per second
LAST_CALL = [0.0]
SKIP_WORDS = ("logo", "map", "diagram", "badge", "emblem", "engine", "seat", "wheel only")


def curl_json(url: str, attempts: int = 4) -> dict | None:
    """Polite GET with pacing and backoff; Wikimedia throttles aggressive clients."""
    import subprocess

    for attempt in range(attempts):
        wait = MIN_INTERVAL - (time.time() - LAST_CALL[0])
        if wait > 0:
            time.sleep(wait)
        LAST_CALL[0] = time.time()
        try:
            out = subprocess.run(
                ["curl", "-sS", "--max-time", "30", "-A", UA, url],
                capture_output=True, text=True, timeout=40,
            ).stdout
        except Exception:
            time.sleep(1.5 * (attempt + 1))
            continue
        if "too many requests" in out.lower():
            time.sleep(4.0 * (attempt + 1))
            continue
        try:
            return json.loads(out)
        except Exception:
            time.sleep(1.5 * (attempt + 1))
    return None


def search(query: str, limit: int = 6) -> list[dict]:
    params = {
        "action": "query", "generator": "search", "gsrsearch": query,
        "gsrnamespace": 6, "gsrlimit": limit, "prop": "imageinfo",
        "iiprop": "url|size|mime|extmetadata", "iiurlwidth": 1400, "format": "json",
    }
    data = curl_json(API + "?" + urllib.parse.urlencode(params))
    if not data:
        return []
    pages = data.get("query", {}).get("pages", {})
    out = []
    for page in pages.values():
        info = (page.get("imageinfo") or [{}])[0]
        title = page.get("title", "").replace("File:", "")
        if info.get("mime") not in ("image/jpeg", "image/png"):
            continue
        if any(word in title.lower() for word in SKIP_WORDS):
            continue
        meta = info.get("extmetadata", {})
        out.append(
            {
                "title": title,
                "url": info.get("thumburl") or info.get("url"),
                "width": info.get("width"),
                "height": info.get("height"),
                "license": (meta.get("LicenseShortName", {}) or {}).get("value", ""),
                "author": re.sub(r"<[^>]+>", "", (meta.get("Artist", {}) or {}).get("value", "")),
                "page": f"https://commons.wikimedia.org/wiki/File:{urllib.parse.quote(title)}",
            }
        )
    return out


def download(url: str, path: Path) -> bool:
    import subprocess

    result = subprocess.run(
        ["curl", "-sS", "--max-time", "60", "-A", UA, "-o", str(path), url],
        capture_output=True,
    )
    if result.returncode != 0:
        return False
    try:
        with Image.open(path) as im:
            im.verify()
        return True
    except Exception:
        path.unlink(missing_ok=True)
        return False


def score(path: Path) -> dict:
    """Heuristic usefulness score: side-on framing, plain backdrop, subject size."""
    with Image.open(path) as im:
        im = im.convert("RGB")
        im.thumbnail((600, 600))
        a = np.asarray(im).astype(float)
    h, w = a.shape[:2]
    aspect = w / max(h, 1)

    ring = np.concatenate([
        a[0, :, :], a[-1, :, :], a[:, 0, :], a[:, -1, :],
    ])
    bg_spread = float(ring.std())

    grey = a.mean(axis=2)
    centre = grey[int(h * 0.25) : int(h * 0.85), int(w * 0.15) : int(w * 0.85)]
    contrast = float(centre.std())

    aspect_score = 1.0 - min(abs(aspect - 1.85) / 1.2, 1.0)
    bg_score = 1.0 - min(bg_spread / 60.0, 1.0)
    contrast_score = min(contrast / 55.0, 1.0)
    return {
        "aspect": round(aspect, 2),
        "bg_spread": round(bg_spread, 1),
        "contrast": round(contrast, 1),
        "score": round(0.45 * aspect_score + 0.35 * bg_score + 0.20 * contrast_score, 3),
    }


def contact_sheet(items: list[tuple[str, Path]], destination: Path, columns: int = 6) -> None:
    if not items:
        return
    cw, ch, label = 300, 210, 18
    rows = (len(items) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * cw + 12, rows * (ch + label) + 12), (10, 13, 20))
    draw = ImageDraw.Draw(sheet)
    for index, (caption, path) in enumerate(items):
        try:
            im = Image.open(path).convert("RGB")
        except Exception:
            continue
        im.thumbnail((cw - 10, ch - 10))
        x = 8 + (index % columns) * cw
        y = 6 + (index // columns) * (ch + label)
        sheet.paste(im, (x, y))
        draw.text((x, y + ch - 6), caption[:44], fill=(130, 142, 160))
    sheet.save(destination)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--per-family", type=int, default=3)
    parser.add_argument("--only", type=str, help="substring filter on brand")
    parser.add_argument("--limit-families", type=int)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument("--skip-existing", action="store_true")
    args = parser.parse_args()

    families = F.load_families()
    todo = [(b, f, m) for (b, f), m in families.items()]
    if args.only:
        todo = [t for t in todo if args.only.lower() in t[0].lower()]
    todo.sort(key=lambda t: (-len(t[2]), t[0]))
    if args.limit_families:
        todo = todo[: args.limit_families]

    args.out.mkdir(parents=True, exist_ok=True)
    manifest, best_picks = [], []
    for index, (brand, family, models) in enumerate(todo, 1):
        slug = f"{F.slug(brand)}-{F.slug(family)}"
        folder = args.out / slug
        if args.skip_existing and folder.exists() and any(folder.iterdir()):
            print(f"[{index}/{len(todo)}] {slug}: cached")
            continue

        queries = [f"{brand} {m}" for m in models[:3]]
        seen, candidates = set(), []
        for query in queries:
            for hit in search(query, limit=5):
                if hit["title"] in seen or not hit["url"]:
                    continue
                seen.add(hit["title"])
                candidates.append(hit)
            pass
            if len(candidates) >= args.per_family * 2:
                break

        folder.mkdir(parents=True, exist_ok=True)
        scored = []
        for n, hit in enumerate(candidates[: args.per_family]):
            path = folder / f"cand-{n}.jpg"
            if not path.exists() and not download(hit["url"], path):
                continue
            if not path.exists():
                continue
            info = score(path)
            scored.append((info["score"], path, hit, info))

        scored.sort(key=lambda s: -s[0])
        for rank, (sc, path, hit, info) in enumerate(scored):
            renamed = folder / f"{rank:02d}-{sc:.2f}.jpg"
            if path != renamed and path.exists():
                path.rename(renamed)
            manifest.append(
                {
                    "family_slug": slug, "brand": brand, "family": family,
                    "models": len(models), "rank": rank,
                    "image": str(renamed.relative_to(ROOT)), "score": sc,
                    "aspect": info["aspect"], "bg_spread": info["bg_spread"],
                    "title": hit["title"], "license": hit["license"],
                    "author": hit["author"].strip()[:80], "page": hit["page"],
                }
            )
            if rank == 0:
                best_picks.append((slug, renamed))
        print(f"[{index}/{len(todo)}] {slug:34} {len(scored)} candidates, best {scored[0][0]:.2f}" if scored
              else f"[{index}/{len(todo)}] {slug:34} nothing found")

    if manifest:
        path = args.out / "manifest.csv"
        existing = []
        if path.exists():
            with path.open() as handle:
                existing = [r for r in csv.DictReader(handle) if r["family_slug"] not in {m["family_slug"] for m in manifest}]
        with path.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(manifest[0].keys()))
            writer.writeheader()
            writer.writerows(existing + manifest)
        contact_sheet(best_picks, ROOT / "pilot" / "refs-review.png", columns=6)
        print(f"\n{len(best_picks)} families with a candidate -> pilot/refs-review.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
