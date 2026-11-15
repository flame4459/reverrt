# Changelog

Notable changes to **Revert**, newest first. Dates are ISO-8601.

This is a pre-1.0 community project and nothing has been submitted to the App
Store, so "Unreleased" means "what is on `main` today". The long-form design
notes behind the UI work live in [PHASE0](PHASE0_BASELINE.md) →
[PHASE5](PHASE5_FINAL_POLISH.md), and the feature debate lives in
[FEATURE_OUTLINE.md](FEATURE_OUTLINE.md).

## [Unreleased] — 2026-11-15

### Added

**Ride Lab** — first integrated pass of the sixteen-feature outline, reachable
from the Home screen:

- *Planning:* sun/light conditions with "you'd finish in the dark" warnings; a
  range ring at 90 % comfortable range; multi-day trips, one card per day; the
  saved loop deck; GPX import with an optional MapKit re-plan; serverless route
  links; an offline preflight that packs roads and hazards around the start.
- *In the ride:* "mark hazard" and "avoid this road" voice marks (the same
  actions are in the ride menu); ghost chase against your fastest previous run on
  the same route; long-ride battery mode that dims the cockpit after ten seconds
  at speed; Focus mode that hides the map dock but keeps a visible exit.
- *After the ride:* ride the exact track again from History; a corner report with
  entry/apex/exit speed and lean; a monthly recap poster rendered to PNG; setup
  and tyre notes per bike; local segment detection.
- *Platform:* a "Start my usual loop" Siri shortcut that picks the saved loop
  with the most completed rides.

**Ride debug transcripts** — on by default, one plain-text file per ride:
settings in force, every alert with both rider and device position, every
withheld announcement and why (`under-speed-gate`, `cooldown`, `already-announced`,
…), a position sample every 5 s, the full route step table, and
`NAV-*` / `WIDGET-*` / `LIVE-*` events. Share or delete from **Settings → Ride
debug**; the newest 40 are kept.

**Route-planning resilience**

- Planned graphs are cached on disk, keyed by a deterministic hash of the road
  set. A start point that is not already a node snaps to the nearest one
  (~220 m chunks) instead of invalidating the cache.
- When MapKit has no driving route — no signal, or a destination it refuses —
  directions fall back to A\* over the on-device graph, fetching only a corridor
  of roads around the line and splitting long trips into overlapping slices.
- Road geometry is stored as overlapping saved *areas*, so re-planning in a warm
  region only fetches what is actually missing.

**Offline** — a whole trip region can be prepared in one go: radii above 20 km
are split into overlapping 20 km cells and filled one at a time. Roads and
hazards are fetched as whole areas, concurrently, instead of one request per
5.5 km tile.

**Units** — **Automatic / Metric / Imperial** in Settings, applied to every
distance, speed, elevation, voice prompt and widget; switchable mid-ride from the
cockpit menu; the old metric toggle is migrated once.

**CarPlay without the entitlement** — since iOS 26, widgets and Live Activities
appear on the CarPlay Dashboard with no CarPlay entitlement, so a device build now
ships a live ride card (next manoeuvre, distance, ETA) and a "Start a loop"
launcher, even though the full car-side CarPlay app still needs Apple's approval.

**New modules** — crash reporter and debug archive, shared ride replay, street
name lookup, region coverage/prep, lane guidance, rivals, sprint planner, road
preference editor, saved places, widget diagnostics screen, plus the
`ScaledFont` / `ScreenHeader` / `RevertFormat` foundation for the UI.

### Changed

- **Deployment target lowered from iOS 26.0 to iOS 17.4** — the app now runs on
  iPhone XS and later. Newer APIs sit behind availability checks.
- **Six-phase UI overhaul** (see [PHASE0](PHASE0_BASELINE.md) →
  [PHASE5](PHASE5_FINAL_POLISH.md)):
  - Dynamic Type everywhere: **472 fixed font call sites** migrated to scaled
    fonts.
  - One header layout, semantic colour roles, and a single number/date formatter.
  - Home, Routes and Plan recomposed; the destination input moved into the Home
    hero.
  - The cockpit is motorcycle-first: speed and next turn are the hero, lean is
    the signature metric, and the car HUD is a lighter variant.
  - History and Insights merged their duplicated summaries; Summary numbers moved
    off the map.
  - Compact headers on every secondary screen, larger hit targets, tab-bar pass.
- Widget and Live Activity rewritten around the same shared state, with reloads
  forced on manoeuvre changes.
- Bike sprites regenerated: **959 images** updated from the new reference set.

### Removed

- `revert/DirectionsView.swift` (2,223 lines) — its responsibilities moved into
  the recomposed Routes and Plan surfaces.

### Fixed

- Lean gained its own colour token across all records surfaces.
- Insights chart no longer plots day-based data on a time-of-day axis.
- Removed the three duplicate elapsed-time readouts in the recording cockpit.
- Off-route detection and lane guidance now covered by tests.

### Tests

- **176 unit tests in 22 suites**, up from 87 — new coverage for lane guidance,
  guidance joins, point-to-point routing, area roads, graph cache, corridor
  chunks, bulk cache format, region coverage and prep, ride debug, unit
  preferences, voice callouts and features.
- A stable accessibility-identifier contract (`revert/AccessibilityID.swift`,
  mirrored in `RevertUITests/UITestID.swift`) asserted by a UI test.

### Known issues

- The GitHub Actions workflow needs a runner with the **Xcode 27 SDK**: 
  `HelmetAudio.swift` uses iOS 27 audio APIs behind `#available`, which older
  SDKs cannot compile. Local builds on Xcode 27.2 are clean.

## [1.0.0] — 2026-11-10

First public release.

### Added

- PolyForm Noncommercial 1.0.0 licence, a "free, non-profit, community project"
  statement in the README and on the About screen, and a `whoopteh` credit with a
  `WHOOPTEH` mark on exported posters.
- Issue forms for bug reports and feature ideas, plus the README "Bugs and ideas"
  section.
- Repository description and topics.

### Changed

- **Renamed everything to Revert**: `revvert/` → `revert/`, `revvert.xcodeproj` →
  `revert.xcodeproj`, app product `Rider.app` → `Revert.app`, targets, schemes and
  module `Revert*`, bundle IDs `com.davidmolina.Revert*`, App Group
  `group.com.davidmolina.Revert`, URL scheme `revert://`, GPX namespace
  `revert:`, User-Agent `RevertApp/0.1`, and the Swift type prefixes
  `Rider*` → `Revert*`.

### Removed

- Third-party Waze voice-pack audio from the repository; the app degrades
  gracefully without it.

## [0.1.0] — 2026-11-04

Initial snapshot: twisty-loop planner, turn-by-turn navigation, ride recording
with lean angle, history and replay, garage, story posters, Waze voice packs,
GPX import/export, home widget, Live Activity and CarPlay (simulator builds).
