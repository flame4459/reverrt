# Phase 3 — Cockpit

Status: **complete**. This phase applied **D2-A**: the cockpit is
motorcycle-first, speed and next turn are the hero, and lean is the signature
metric. The car HUD is a lighter variant rather than the default layout.

- Date: 2026-11-14
- Reference set: `.ui-baseline/phase3/` (local, gitignored)
- Before/after: `cockpit-before-after.png` in the reference set
- All screens: `contact-sheet.png` in the reference set
- Inventory after: `.ui-baseline/phase3/token-inventory.md`

## The duplication that was removed

Before, the recording car cockpit showed:

- three elapsed-time readouts: the recording chip, the `DRIVE` card, and the
  `TIME` stats tile;
- current speed twice: the big number and `0 mph • 0.0 mi` in the `DRIVE` card;
- current speed a third time under `Turn right` in the maneuver banner;
- a full-width card for one line of vehicle information;
- a large G-force radar competing with the stats;
- a `NO DATA` placeholder for an unknown speed limit.

After:

- **one timer**: the recording chip is the only elapsed-time readout;
- **one speed**: the speedometer card; the banner no longer repeats it;
- **three stats**: Distance, Climb, Peak;
- **one compact vehicle line**: `CAR MODE · Friends' car · 0.00 G`, with G as a
  car readout rather than a second hero;
- **no placeholder**: the limit sign appears only when a limit is known, and
  the progress bar is hidden without a limit.

The new contract test `testRecordingCockpitHasNoDuplicateStats` asserts that
`DISTANCE`/`CLIMB`/`PEAK` exist and that `TIME`, `DRIVE` and `NO DATA` do not.

## No-route state

`nav.route == nil` and not recording now shows a real next step instead of a
fake `READY / 0 MPH / NO DATA` dashboard:

- “No route yet”
- “Plan a route” (ghost) → dismisses the cockpit and opens Routes
- “Start free ride” / “Start free drive” (primary)

`RideView` gained an optional `onPlanRoute` hook; `PulseShellView` supplies it.
The shell test `testCockpitNoRouteOpensPlanner` covers the path.

## Motorcycle-first

- Bike recording: speedometer, then the lean arc full-width, then the three
  stats. G-force is gone from the live bike HUD.
- Car recording: speedometer, three stats, and a compact G value in the
  caption. The G radar is no longer part of the live panel.
- If the motion sensor is unavailable, the cockpit shows the existing
  “Motion sensor unavailable” card instead of a dead lean gauge.
- The G-force sensor only starts for car rides.

## Map rail

The left dock is now three controls instead of five:

1. Ride menu
2. Recenter
3. Voice commands

Mute and camera mode moved into the ride menu; camera modes were already
listed there, and mute is now the first item. This keeps the voice command
reachable while cutting the rail from roughly 250pt to 150pt.

## Density

- Car recording panel: roughly **53% → 32%** of the display.
- No-route panel: roughly **28%** of the display.
- Bike recording panel: around 47% (lean gauge + three stats). It is shorter
  than before because the G radar and duplicate time tile are gone; a
  two-detent drawer remains a Phase 5 candidate if the gauge needs more map.
- The maneuver banner is shorter because the current-speed line was removed.

## Tests

- Contract suite: **8/8**, including the new de-duplication test and the
  no-route `planRoute` action.
- Shell suite: **11/11**, including `testCockpitNoRouteOpensPlanner` and the
  existing live record/save flow.
- Total across both suites: **19 tests**.
- App build: passed.

## Remaining

- The simulator’s primary vehicle is a car, so the bike cockpit was built and
  compiled but not visually captured in this pass. The code path is speed →
  lean gauge → three stats; verify on a device with motion available.
- The bike recording panel is still around 47%; a compact/two-detent panel is
  a Phase 5 candidate.
- The landscape car panel uses the new three-stat view but was not visually
  re-captured; the landscape shell test is Home/Routes, not the cockpit.
- The G radar is now unused in the live HUD; it is a candidate for the
  post-ride summary in Phase 4.
- Camera cycling is now in the menu instead of a one-tap dock button. The
  recenter button remains one-tap.
