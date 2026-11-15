# Phase 4 — Records

Status: **complete**. This phase merged the duplicate History summaries,
replaced the broken Insights chart, and moved the Summary’s key numbers off the
map. Lean now has its own token throughout the records surfaces.

- Date: 2026-11-14
- Reference set: `.ui-baseline/phase4/` (local, gitignored)
- Records before/after: `records-before-after.png` in the reference set
- All screens: `contact-sheet.png` in the reference set
- Inventory after: `.ui-baseline/phase4/token-inventory.md`

## 1. History: two cards became one

Before, History showed an “All-time snapshot” card and a “Personal bests” card
back to back. They repeated max lean, longest ride and total time, and the
“distance per ride” chart used a time-of-day axis for day-based data.

Now there is one `RideStatsOverview` card:

- total distance as the hero (`114.3 mi`);
- average ride, total time, climbed;
- longest, fastest average, max lean (or cars), top speed.

Each value appears once. The chart is gone; every recent-ride row now carries a
thin distance bar, so the list itself shows relative ride length at any ride
count. The row date, top speed and lean use the shared formatter and
`Pulse.lean`.

## 2. Insights: rows, not two bars in ten slots

The old activity chart forced two rides into ten slots, so 80% of the plot was
empty and both bars were full height. It is now a per-ride list (newest eight):

`Nov 11  ██████████  57.2 mi  1 h 30 m`

Each row has the date, a distance bar relative to the longest of the set, the
distance and the duration. It works with one ride or twenty.

Other fixes:

- “Total time 3.1 HRS” → “3 h 04 m”.
- “Max lean 44° DEG” → “44°” (no redundant unit).
- Removed “Time in the saddle”, which duplicated total time.
- The remaining analysis rows are Best average speed, Rides this month and Most
  ridden machine.

## 3. Summary: numbers below the map

- Distance, time and average speed moved from a low-contrast overlay on the map
  into a solid bar under it. The map keeps only the “Ride complete” chip.
- The route line now has a dark casing over the muted basemap plus a light
  scrim, so it stays readable over city labels.
- The telemetry card no longer repeats distance, time or average speed. It
  shows Laps (or Sprint), Top speed and Climbed.
- The lean ring now reads `44° / 60°`, so the ring’s fill has a visible scale.
- The Rivals card no longer repeats “On device”; only the Stored row carries
  that privacy note.

## 4. Shared formatting

- Added `RevertFormat.duration`: “42 min”, “1 h 30 m”, “3 h 04 m”.
- Added `RevertFormat.rowDateTime`: “Wed, Nov 11 at 4:04 PM”.
- Lean-specific usages in History (including the per-corner report), Insights
  and Summary now use `Pulse.lean` instead of the generic magenta token.
- `String(format:)` moved from 41 to 42 because `duration` uses one two-digit
  minute format; the rider-facing values still go through `RevertFormat`.

## Verification

- App build: passed.
- Contract suite: **8/8**.
- Shell suite: **12/12**.
- Total: **20 UI tests**.
- New regression: `testHistoryStatsAreMerged` asserts the “Ride stats” card
  exists and the old “All-time snapshot” / “Personal bests” cards do not.
- Affected flows also re-run directly: History stats, History detail back
  navigation, Summary contract, Insights/Secondary sheets.

## Remaining

- The History and Insights headers are still the full detail-style header
  blocks; compacting them is Phase 5 work.
- City labels on the Summary map are dimmed but still present; the route casing
  is the main legibility fix. A fully label-free basemap would need a different
  map style.
- The row bars show relative distance, not a time trend. If a trend chart is
  still wanted, add one with date labels and only at 4+ rides.
- The G radar is still absent from the summary; the Ride model does not store a
  max-G value yet.
- The pre-existing unit-test discovery gap is unchanged.
