#!/usr/bin/env bash
# Cut a regional PMTiles archive out of a larger PMTiles source, hash it, and
# add it to the app's MapRegions.json catalog.
#
# Usage:
#   Scripts/maps/build-region.sh \
#     --id long-island --name "Long Island" --subtitle "New York" \
#     --bbox -73.95,40.55,-71.85,41.20 \
#     --source https://tiles.immersivemap.dev/20260922.pmtiles \
#     --download-base https://maps.example.com/regions
#
# Requires the `pmtiles` CLI:
#   brew install pmtiles            (macOS)
#   go install github.com/protomaps/go-pmtiles@latest
set -euo pipefail

ID="" NAME="" SUBTITLE="" BBOX="" SOURCE="" BASE=""
OUT_DIR="$(cd "$(dirname "$0")" && pwd)/build"
CATALOG="$(cd "$(dirname "$0")/../.." && pwd)/revert/MapRegions.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) ID="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --subtitle) SUBTITLE="$2"; shift 2 ;;
    --bbox) BBOX="$2"; shift 2 ;;
    --source) SOURCE="$2"; shift 2 ;;
    --download-base) BASE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ID" && -n "$NAME" && -n "$BBOX" && -n "$SOURCE" ]] || {
  echo "Missing --id, --name, --bbox or --source" >&2; exit 2
}
command -v pmtiles >/dev/null || {
  echo "pmtiles CLI not found. Install with: brew install pmtiles" >&2; exit 2
}

FILE="Revert-${ID}.pmtiles"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$FILE"

echo "Extracting $ID from $SOURCE …"
pmtiles extract "$SOURCE" "$OUT" --bbox="$BBOX"

SIZE=$(stat -f%z "$OUT" 2>/dev/null || stat -c%s "$OUT")
SHA=$(shasum -a 256 "$OUT" | awk '{print $1}')
DOWNLOAD_URL="${BASE:+$BASE/}${FILE}"

python3 - "$CATALOG" "$ID" "$NAME" "$SUBTITLE" "$FILE" "$SIZE" "$SHA" "$BBOX" "$DOWNLOAD_URL" <<'PY'
import json, sys, os
catalog_path, rid, name, subtitle, filename, size, sha, bbox, url = sys.argv[1:10]
min_lon, min_lat, max_lon, max_lat = (float(x) for x in bbox.split(","))
entry = {
    "id": rid, "name": name, "subtitle": subtitle, "fileName": filename,
    "byteSize": int(size), "sha256": sha,
    "bbox": {"minLat": min_lat, "minLon": min_lon, "maxLat": max_lat, "maxLon": max_lon},
    "version": 1, "downloadURL": url,
}
if os.path.exists(catalog_path):
    with open(catalog_path) as f:
        catalog = json.load(f)
else:
    catalog = {"version": 1, "regions": []}
catalog["regions"] = [r for r in catalog["regions"] if r.get("id") != rid] + [entry]
with open(catalog_path, "w") as f:
    json.dump(catalog, f, indent=2)
    f.write("\n")
print(f"Wrote {filename} ({int(size)/1e6:.1f} MB) and updated {catalog_path}")
PY

echo "Done: $OUT"
