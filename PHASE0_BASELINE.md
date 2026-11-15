# Phase 0 — Baseline, test contract, and entry criteria

Status: **complete except for three product decisions** that Phase 2/3 need.
No visual or behavioural app changes landed; this phase only added stable
identifiers, test infrastructure, and measurement.

- Date: 2026-11-14
- Build used for the baseline: `1.0 (1)`, Debug, iPhone 17 Pro (iOS 26.4)
- Baseline screens: `.ui-baseline/phase0/` (local, gitignored)
- Token inventory: `.ui-baseline/phase0/token-inventory.md`

## What landed

### 1. Stable accessibility contract

- `revert/AccessibilityID.swift` is the single app-side list of identifiers.
- `RevertUITests/UITestID.swift` mirrors it for the black-box test bundle.
- `RevertUITests/AccessibilityContractUITests.swift` asserts that every main
  screen and primary control exposes its identifier.
- `RevertUITests/PulseShellUITests.swift` now queries those identifiers instead
  of screen copy.

The shell suite previously asserted `"Your machines"` while the Garage screen
rendered `"Your vehicles"`; that stale copy assertion is gone.

### 2. Repeatable screenshot baseline

```bash
# with a booted simulator that already has Revert installed
./Scripts/capture-ui-baseline.sh .ui-baseline/phase0
```

The script freezes the status bar at 9:41, launches each screen with the
existing debug arguments, and writes a manifest beside the PNGs. It captures:

`home`, `routes`, `plan`, `cockpit-idle`, `cockpit-recording`, `history`,
`garage`, `settings`, `insights`, `safety`, `posters`, `summary`, `onboarding`.

The PNGs are intentionally gitignored; the manifest records the app version,
simulator, launch arguments, fixed location, and settle time. For a true
first-run baseline, use a dedicated simulator or uninstall/reinstall before
capturing.

### 3. Location-aware UI test runner

```bash
./Scripts/run-ui-tests.sh -only-testing:RevertUITests/PulseShellUITests
```

A simulator with no location fix makes the planner and live-ride tests flaky,
and a static fix cannot record a ride. The wrapper starts the “City Bicycle
Ride” scenario, resolves the booted simulator automatically, and clears the
location on exit. Use it for any UI run that touches planning or recording.

### 4. Token inventory

```bash
./Scripts/ui_token_inventory.sh > .ui-baseline/phase0/token-inventory.md
```

Current measurement of `revert/**/*.swift`:

| Metric | Count |
|---|---:|
| Fixed `.font(.system(size:))` | 472 |
| Semantic `.font(.system(.style, ...))` | 162 |
| `relativeTo:` (Dynamic Type) | 0 |
| Distinct fixed sizes | 33 (7pt–76pt) |
| `PulseScreenHeader` usages | 5 |
| `RevertScreenHeader` usages | 12 |
| `cornerRadius` references | 227 |
| Hex colour literals | 140 |
| `Color(red:)` literals | 59 |
| `String(format:)` calls | 60 |
| `accessibilityIdentifier` references | 33 |

Two parallel systems remain: `PulseScreenHeader` + `PulseMetrics` (17pt cards,
19pt padding) and `RevertScreenHeader` + `RevertMetrics` (18pt cards, 18pt
padding, 22pt dock radius). Phase 1 collapses these; Phases 2–5 must not add
new literals.

## Verification

```bash
# App build
xcodebuild build -project revert.xcodeproj -scheme Revert \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build-phase0 CODE_SIGNING_ALLOWED=NO

# Contract suite (7 tests)
./Scripts/run-ui-tests.sh \
  -only-testing:RevertUITests/AccessibilityContractUITests

# Shell/navigation suite (9 tests)
./Scripts/run-ui-tests.sh \
  -only-testing:RevertUITests/PulseShellUITests
```

Results on this machine:

- App build: passed.
- `AccessibilityContractUITests`: **7/7 passed**.
- `PulseShellUITests`: **9/9 passed** with the moving location scenario,
  including the live-record/save flow and the route-search/start-navigation
  flow.
- Without a location scenario, `testLiveRideStartsAndSaves` skips with a clear
  message instead of failing on a UI timeout; everything else still runs.

### Test ownership going forward

| Suite | State | Migrate |
|---|---|---|
| `AccessibilityContractUITests` | identifier-based | maintain with each phase |
| `PulseShellUITests` | migrated for shell/navigation/primary CTAs | keep green every phase |
| `RevertUITests` | copy-coupled | Phase 2–3, as those screens change |
| `RevertFlowUITests` | copy-coupled | Phase 4 (history/poster flows) |
| `RevertAuditUITests` | copy-coupled, scripted walkthrough | Phase 5 |

Do not rename visible copy in a phase without updating the matching suite in
the same PR, or add the identifier first and migrate the assertion.

## Decisions needed before Phase 2/3

These were listed in the review. Phase 0 records a recommendation for each;
none block Phase 1.

### D1 — Home hero

- **A (recommended):** make the hero the route input. One large “Where to?”
  field and one primary action, deep-linked into the planner with focus. This
  removes the Home → Routes “lobby to a lobby” hop.
- **B:** keep the billboard, shrink the header, and move Quick Access above
  the stats. Smaller Phase 2, but Home stays a dashboard of links.

Recommendation: **A**. It is the single biggest hierarchy change and makes the
Home primary action real.

### D2 — Cockpit default

- **A (recommended):** motorcycle-first. Speed + next turn + lean arc are the
  hero; distance/time/climb collapse to one strip. Car mode keeps G-force and
  drops the duplicate “DRIVE” card.
- **B:** keep the current car-first panel and adapt the bike around it.

Recommendation: **A**. Leaning is the product’s signature data; it should not
be a secondary card.

### D3 — Ride Lab placement

- **A (recommended):** remove it from Home Quick Access; put it behind a single
  “Explore” row in Settings, or one link after the core Home actions.
- **B:** keep it as a fifth Quick Access tile.

Recommendation: **A**. It is a 16-feature hub with the same visual weight as
Garage and History, which flattens the Home hierarchy.

### Assumption for Phase 1 (no decision needed)

Preserve the current default-size appearance while adding Dynamic Type:
replace fixed sizes with `.system(size:relativeTo:)` at the same numeric size,
then adjust layouts only where AX sizes break. The cockpit may clamp at
`.accessibility2`; the rest of the app should follow the system setting.

## Phase 1 entry checklist

- [ ] Confirm D1–D3.
- [ ] Merge Phase 0 (identifiers + tests + scripts).
- [ ] Capture a post-merge baseline: `./Scripts/capture-ui-baseline.sh`.
- [ ] Add one type scale (`PulseType` + `RevertType` collapse) with
      `relativeTo:`; no visual size changes at default.
- [ ] Collapse the two header components into one with `.full` / `.compact`.
- [ ] Define semantic colours: accent, positive, caution, danger, lean.
- [ ] Introduce one number/date formatter and migrate the `String(format:)`
      call sites (odometer, elevation, distances).
- [ ] Apply 44pt hit areas to `PulseCircleButton`, `PulseTag`,
      `PulseSegmented`, and the tab bar.
- [ ] Re-run `ui_token_inventory.sh`: fixed sizes may remain during the
      migration, but `relativeTo:` must be non-zero and no new size literals
      may be added.
- [ ] Re-run the contract suite; all 7 green.
- [ ] Review the Phase 1 diff as a visual no-op at default text size.

## Known gaps

- The `RevertTests` unit scheme reports “0 tests” on this Xcode 27.2 / iOS 26.4
  setup even though the bundle builds and is embedded in the app. The tests use
  Swift Testing (`@Test`), not XCTest. This is pre-existing and unrelated to
  Phase 0; it should be fixed before the Phase 5 release gate so the UI work is
  covered by the algorithm/unit suite as well.
- The iOS 26.4 simulator test runner occasionally crashes while snapshotting a
  Map view and restarts the remaining suite. The green run used
  `-retry-tests-on-failure`; all 7 contract tests passed on iteration 1. Keep
  the flag in CI until the runtime issue is resolved.

## Build note

On this machine, running `xcodebuild` inside the agent’s file sandbox makes
`swift-plugin-server` return malformed responses for `@Observable`/`@State`
macros. The same build succeeds with unrestricted file access. This is an
Xcode 27.2 + sandbox interaction, not a source error. If a CLI build fails with
“external macro implementation type … could not be found”, restart the plugin
server (`pkill -f swift-plugin-server`) and run the build outside the sandbox.
