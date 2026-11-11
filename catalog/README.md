# Catalog sources

* `motorcycle_8bit_prompts.xlsx` — the master model list (brand, category,
  family, model, approximate years) plus the prompt used to render each 8-bit
  sprite. This is the source of truth for what appears in the bike picker.
* `legacy_bikes.txt` — the hand-curated entries that predate the workbook. They
  are kept verbatim because their names are wired to finished sprites, saved
  selections and the widget snapshot.

Both feed `Scripts/generate_bike_catalog.py`, which writes
`revert/BikeCatalogData.swift` (`Brand|Model|Years|Category` per line)
and prints a report of workbook rows it skipped because a legacy entry already
covers that model.

```sh
python3 Scripts/generate_bike_catalog.py            # regenerate
python3 Scripts/generate_bike_catalog.py --dry-run  # merge report only
```

The merge is additive: legacy entries always win, and a workbook row is only
added when no legacy entry describes the same model (spacing differences such
as `S1000RR` vs `S 1000 RR` are normalised; a trailing engine size such as
`Monster 400` still counts as a distinct model).
