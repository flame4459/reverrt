# Phase 1 — Foundations

Status: **complete**. This phase changed typography, headers, semantic colour
tokens, number/date formatting, and hit targets. It did not redesign Home,
Routes, the cockpit, or the data screens; those compositions remain Phase 2–4.

- Date: 2026-11-14
- Reference set: `.ui-baseline/phase1/` (local, gitignored)
- Inventory after: `.ui-baseline/phase1/token-inventory.md`
- Phase 0 before-state: [`PHASE0_BASELINE.md`](PHASE0_BASELINE.md)

## 1. Dynamic Type

- Added [`Font.scaledSystem(size:weight:design:relativeTo:)`](revert/ScaledFont.swift),
  backed by `UIFontMetrics`. It infers the closest text style from the base
  size unless a caller supplies one, so 8pt captions and 58pt speed numbers
  scale on different curves.
- Migrated **472 of 472** fixed view-font call sites from
  `.font(.system(size:))` to `.font(.scaledSystem(size:))`.
- Collapsed `RevertType` onto `PulseType`; both now read the same scale.
  `PulseType.display`, `.number`, `.eyebrow`, `.section`, `.body` and
  `.headline` all scale.
- Verified at the default category and at extra-extra-large. Changing the
  simulator content size while Settings is open reflows the screen without a
  relaunch.

At the default content-size category the sizes are unchanged: onboarding is
**pixel-identical** to the Phase 0 capture. Settings and Safety shift by roughly
1px of text metrics (mean absolute channel difference < 4/255; < 5% of pixels
differ by more than 8 levels) with no layout change.

## 2. One header layout

- Added [`ScreenHeader.swift`](revert/ScreenHeader.swift) with `.dashboard`,
  `.detail`, and `.compact` variants.
- `PulseScreenHeader` and `RevertScreenHeader` are now thin compatibility
  wrappers, so all 17 existing call sites keep their visual treatment.
- `.compact` is available for Phase 2, where screen headers replace the
  oversized title blocks. It is not adopted yet.
- The accessibility-identifier contract still passes: both wrappers forward
  the title identifier.

## 3. Semantic colour roles

Added to `Pulse`:

| Role | Token | Current value |
|---|---|---|
| Action | `Pulse.action` | palette accent |
| Positive | `Pulse.positive` | emerald |
| Caution | `Pulse.caution` | palette warning |
| Danger | `Pulse.danger` | coral-red |
| Lean | `Pulse.lean` | magenta |

Lean-specific usages now call `Pulse.lean` in the summary ring, insights max
lean, cockpit lean gauge, and the lean heat-map band. `MapUI.cyan` and
`MapUI.emerald` now resolve through `Pulse.action` / `Pulse.positive`. The
visual output is unchanged; the roles are now addressable.

## 4. One number/date formatter

Added [`RevertFormat.swift`](revert/RevertFormat.swift):

- `number(_:decimals:)` is locale-aware with automatic grouping.
- `shortDate`, `mediumDate`, `fullDateTime`, `dayNumber`,
  `monthAbbreviation` centralise the existing date formats.

`Units` now uses `RevertFormat` for speed, distance, elevation, short approach
distances and spoken approach distances. Odometer and elevation values gained
thousands separators:

| Before | After |
|---|---|
| `11433 mi` | `11,433 mi` |
| `8136 ft` | `8,136 ft` |
| `3520 km` | `3,520 km` |
| `4068 ft` | `4,068 ft` |

Home, History and Summary use the shared date helpers. The loop-distance
presets, reaction-time setting, G-force readout and tyre-pressure note also use
`RevertFormat`. `String(format:)` calls dropped from 60 to 41; the remainder are
machine/log/coordinate strings, the fixed `h:mm:ss` clock, and diagnostics.

## 5. Hit targets and tab bar

- `PulseCircleButton`: visual circle stays 37pt, hit target is now 44×44.
- `PulseSegmented`: segment height 32 → 44.
- Tab bar: item content minimum 44pt, label size 8.5 → 10.5.
- `PulseTag` remains 23pt high but is non-interactive; no hit target required.

## Verification

```bash
# App build
xcodebuild build -project revert.xcodeproj -scheme Revert \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build-phase0 CODE_SIGNING_ALLOWED=NO

# All UI tests with a moving simulator location
./Scripts/run-ui-tests.sh \
  -only-testing:RevertUITests/AccessibilityContractUITests \
  -only-testing:RevertUITests/PulseShellUITests
```

Results:

- App build: passed.
- `AccessibilityContractUITests`: **7/7 passed**.
- `PulseShellUITests`: **9/9 passed**, including live record/save and
  route-search/start-navigation.
- Total: **16/16 UI tests**, no retries needed on the final run.
- Dynamic Type: default, XXL, and live category change verified.

## Inventory: before → after

| Metric | Phase 0 | Phase 1 |
|---|---:|---:|
| Fixed `.font(.system(size:))` call sites | 472 | **0** |
| Dynamic-Type font call sites | 0 | **472** |
| Semantic `.font(.system(.style))` | 162 | 162 |
| Distinct base sizes | 33 | 33 |
| Header layouts | 2 | **1** (+ 2 wrappers) |
| `String(format:)` calls | 60 | **41** |
| Circle-button hit target | 37pt | **44pt** |
| Segmented-control height | 32pt | **44pt** |
| Tab label | 8.5pt | **10.5pt** |
| Tab item min height | ~40pt | **44pt** |
| `accessibilityIdentifier` references | 33 | 32 |

The 33 distinct base sizes were deliberately preserved: Phase 1 changes how
those sizes scale, not which sizes the design uses. Rationalising the scale
itself is Phase 2/5 work and must be done screen by screen against screenshots.

## Remaining work for later phases

- **Phase 2:** adopt `ScreenHeader(.compact)` on Home/Routes; drop the oversized
  header blocks. Rationalise duplicate sizes (7–76pt) where a screen is being
  recomposed anyway.
- **Phase 3:** decide whether the cockpit clamps Dynamic Type at
  `.accessibility2`; audit the HUD at large categories.
- **Phase 4:** migrate remaining data-screen date/number formatting and lean
  colours in History.
- **Phase 5:** full AX-size audit (Settings/History rows can wrap at XXL), and
  the pre-existing unit-test discovery gap (`RevertTests` reports 0 tests).
- Screen-specific 30–37pt controls (map buttons, quick-action wells) remain;
  fix them in the phase that touches each screen.

## Not in this phase

The three product decisions from Phase 0 are still open: D1 Home hero,
D2 cockpit default, D3 Ride Lab placement. None of them block the foundation
work, and Phase 1 did not change those compositions.
