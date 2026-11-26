# Offline map regions

Revert's immersive renderer reads a PMTiles archive. By default it streams one
from the hosted planet archive, which is 138 GB and needs a connection. To ride
without signal, cut a **regional extract** and ship it in the app (starter) or
host it for download.

## Pipeline

```bash
brew install pmtiles        # or: go install github.com/protomaps/go-pmtiles@latest
Scripts/maps/build-region.sh \
  --id long-island --name "Long Island" --subtitle "New York" \
  --bbox -73.95,40.55,-71.85,41.20 \
  --source https://tiles.immersivemap.dev/20260922.pmtiles \
  --download-base https://maps.example.com/regions
```

The script:

1. `pmtiles extract --bbox` cuts the region from the source archive.
2. Computes its size and SHA-256.
3. Adds an entry to `revert/MapRegions.json`, the catalog the app ships.

The file lands in `Scripts/maps/build/`, which is git-ignored. Upload it to
static hosting (object storage or any CDN is enough — no map server is needed)
and use that prefix as `--download-base`.

## Starter region

To bundle a starter map: copy the extract to `revert/region.pmtiles` and build.
The app treats `region.pmtiles` as the starter archive, shows it as "Included",
and prefers a downloaded region over it when both cover the rider.

Because the file is large, commit it with Git LFS (or don't commit it at all and
rely on downloads):

```bash
git lfs track "revert/region.pmtiles"
cp Scripts/maps/build/Revert-starter.pmtiles revert/region.pmtiles
```

## Choosing the source

- **Hosted ImmersiveMap archive** (`tiles.immersivemap.dev`): same vector-tile
  schema the renderer styles, so extracts look identical. Check the host's terms
  before redistributing extracts.
- **Your own bake** (`planetiler` / `tilemaker` from an OSM extract): keeps the
  pipeline fully yours, but you must match the layer names ImmersiveMap's style
  expects, or write your own style.

## Budgets

| Region | Typical extract |
| --- | --- |
| A metro area | 20–150 MB |
| A US state | 200–800 MB |
| A country | 1–5 GB |

Extracts are zoom-limited by the source (z15 on the hosted archive). Regions
that large should not be bundled into the app download — ship a starter of a few
hundred MB at most and let riders download the rest over Wi-Fi.

## Attribution

Any extract derived from OpenStreetMap must credit
"© OpenStreetMap contributors" with a link to
<https://www.openstreetmap.org/copyright>. Revert shows that line on the map
and in Settings → Offline maps.

## Testing the pipeline

`build-region.sh` is the only network-dependent step. The app-side contract
(manifest fields, checksum, install/delete, archive selection) is covered by
`RevertTests/MapRegionTests.swift`, which builds header-valid fixture archives
locally.
