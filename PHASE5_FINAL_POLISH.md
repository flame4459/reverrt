# Phase 5 — Final polish

Status: **complete** for the secondary-screen and accessibility pass. The
unit-test discovery gap is documented at the end; it is a toolchain issue, not
a UI regression.

- Date: 2026-11-15
- Reference set: `.ui-baseline/phase5/` (local, gitignored)
- All screens: `contact-sheet.png`
- Secondary before/after: `secondary-before-after.png`
- Inventory: `.ui-baseline/phase5/token-inventory.md`

## 1. Compact headers everywhere

History, Garage, Settings, Insights, Safety and Story Posters now use the
compact header instead of the full icon/eyebrow/subtitle block. The screens
start closer to the content and the section labels inside each screen carry the
context.

Two headers needed more than a size change:

- **History** had an empty navigation bar plus a toolbar import button, which
  left a large dead zone above the title. Import and Close now live in the
  header itself, and the empty bar is hidden. Ride detail still pushes and
  returns correctly.
- **Settings** had the same issue with its Done button. Done is now a header
  action, and the empty bar is gone.

## 2. Garage

- Search is hidden until there are three vehicles; it was noise for one.
- The vehicle card no longer stacks three pills that squeeze the model name.
  It shows the vehicle icon, name, a primary star, two stats (odometer and
  range) and one service status line with a progress bar.
- “Service due” now appears once: the status line and bar, not a pill, a stat
  tile and a footer.
- Make/model is no longer truncated by “Primary” / “Car” / “Service due” chips.
- The lower half now has a **Maintenance** section for the primary vehicle:
  the latest three log entries, or a clear empty state with a View Log link.

## 3. Story posters

- The twelve theme chips were a clipped horizontal carousel. They are now a
  single **Theme** menu that shows the current theme and swatch and opens the
  full list. No clipped chip, no six-row grid.
- The bottom Done button is gone; the header X closes the sheet. “Open studio”
  is the only bottom action and now spans the width.
- The theme menu survives XXL text without clipping.

## 4. Settings and onboarding

- Settings keeps its color-scheme list, but the compact header plus
  header-owned Done exposes Ride & Units much earlier.
- Onboarding’s authorized CTA changed from “Start riding” to **“Enter Revert”**.
  It dismisses to Home, so the label now describes what actually happens.

## 5. Tab bar and Dynamic Type

- The active Home icon uses `house.fill`; colour alone was a weak selection cue.
- The five tab labels are intentionally fixed at 10.5 pt. At XXL the scaled
  labels collided (“GARAGE HISTORY”); five labels cannot grow indefinitely.
  This is the **one** fixed font call in the app, and it is chrome rather than
  content. Icons and all content still scale.
- XXL audit fixes: tab-label collision, poster theme clipping, and History row
  metadata wrapping. 491 Dynamic Type call sites remain; 33 base sizes.

## Verification

- App build: passed.
- UI suite: **20/20** (8 contract + 12 shell).
- Directly re-run after the secondary changes: History detail navigation,
  History merged stats, Garage/History identifiers, Summary/Insights/Settings
  sheets.
- Phase 5 reference set captured after the final build.
- Inventory: 0 `PulseScreenHeader` usages, 19 `ScreenHeader` call sites, 9
  compatibility wrappers, 42 `String(format:)` calls.

## Unit-test discovery gap

`RevertTests` still reports **0 tests** under `xcodebuild test`. This is not a
missing test bundle:

- A temporary XCTest smoke test ran and passed, proving the bundle loads.
- The Swift Testing metadata section (`__swift5_tests`) is present and
  `Testing.framework` is linked.
- Adding the host app to the test scheme’s BuildAction and forcing
  `ENABLE_SWIFT_TESTING=YES` made no difference.
- The temporary test and scheme edit were removed.

This looks like the Xcode 27.2 test-runner/Swift Testing integration. The UI
suite is the current release gate; the unit target should be re-checked on the
next Xcode update or migrated to a test plan.

## Remaining / optional

- Settings still renders five color-scheme rows; a two-column theme grid would
  save another ~150 pt, but the compact header already exposes the next section.
- Garage has a large lower area when the primary vehicle has no maintenance
  entries; the empty state explains where to add one.
- The G radar remains absent from Summary because the Ride model stores no
  max-G value.
- The unit-test discovery gap above.
