# Phase 2 — Home, Routes, Plan

Status: **complete**. This phase recomposed the three surfaces in the “plan a
ride” flow. It applied **D1-A** (the Home hero becomes the destination input)
and **D3-A** (Ride Lab moves out of the primary grid). **D2-A** — the cockpit
default — is still Phase 3.

- Date: 2026-11-14
- Reference set: `.ui-baseline/phase2/` (local, gitignored)
- Home before/after: `home-before-after.png` in the reference set
- All screens: `contact-sheet.png` in the reference set
- Inventory after: `.ui-baseline/phase2/token-inventory.md`

## 1. Home

**Compact header.** `ScreenHeader(.compact)` replaces the eyebrow + 27pt title
block. The header is now a 22pt “Your next ride” row with the colour-scheme
button and a “More” menu.

**The hero is the product.** The old billboard had a subtitle, a “Plan a
route” button that just switched tabs, and an unlabeled cockpit icon. It is now
a real destination input:

- a 50pt “Search a destination” field bound to the same `routes.destination`
  `SceneStorage` the planner uses;
- a full-width “Plan route” button;
- submitting from the keyboard (Go) or tapping the button writes the draft,
  selects the Routes tab, and asks the planner to focus the destination field.

The shell test verifies both halves: Routes opens **and** the typed destination
is already in the planner field.

**Quick access above the fold.** Home order is now header → hero → Quick Access
→ summary → active vehicle → last ride → recent rides. Quick Access starts at
roughly 35% of the viewport, down from roughly 88% in Phase 1. The grid is a
clean 2×2: Cockpit, Insights, Safety, Posters. Ride Lab moved to the “More”
menu, which now contains only Offline maps and Ride Lab.

**One summary line.** The three equal-weight metric cards (“Total rides /
Distance / Bikes”) became a single secondary line:

`3 rides · 114 mi · 1 vehicle`

This fixes the old “Bikes: 1 garage” copy when the only vehicle is a car, and
removes a card row that was not actionable.

**Active vehicle.** The icon now follows the vehicle kind (`car.fill` for a
car), the section is labelled “Active vehicle”, and the odometer reads
`11,433 mi` through the Phase 1 formatter.

**Last ride is labelled last ride.** The route preview section is “Live route”
when navigating, “Last ride” when showing the latest ride, and “Your next
route” only when there is neither.

## 2. Routes

**Compact header.** “Route planner” is now a 22pt compact header, not the
eyebrow + 27pt block.

**A persistent primary action.** The planner has a bottom `safeAreaInset`:

- “Find route” (primary) when a destination is ready;
- “Enter a destination” (ghost, disabled) when the field is empty;
- “Waiting for GPS” when there is no fix;
- “Finding that destination…” / “Building your route…” with a spinner while
  the planner works.

The old in-card “Preview route” button and hint copy are gone; there is one CTA
instead of a button that lived below the fold.

**The empty map is hidden.** The map card only appears once there is a pin, a
route or a stop. With it hidden, Rival Times and Saved Loops move into the
first viewport (Rival Times begins around 43% of the viewport, versus below the
fold in Phase 1). The map returns as soon as a destination resolves.

**Focus hand-off.** `routes.focusOnAppear` is a one-shot flag set by Home.
Routes focuses the destination field on appear (or when the flag changes while
the tab is already alive) and clears it immediately.

## 3. Plan a loop

- Map height 278 → 240pt, giving the controls more room.
- The floating pin switcher now has a “PIN MODE” caption so “Start / Shaping”
  reads as a pin mode, not a second Start button.
- The footer is opaque (no content fading under a transparent gradient) and
  has a top hairline.
- A live summary sits above the CTA:
  `40 mi · Twisty · Paved · 3 laps`
  so the rider sees the settings that “Find scenic loops” will use before
  tapping it.
- The footer still uses `safeAreaInset`, so the content is genuinely inset
  rather than hidden behind the button.

The close control remains the existing top-right circle rather than a
navigation-bar item; moving it would require wrapping the sheet in a
`NavigationStack` and is deferred to the Phase 5 polish pass.

## 4. Tests

Added/updated:

- `AccessibilityContractUITests`: Home now requires `home.destination`, and
  Routes requires `routes.findRoute`.
- `PulseShellUITests`: new `testHomeDestinationOpensPlanner` types a destination
  on Home, submits, asserts that Routes opens, that the destination value was
  carried across, and that the footer CTA exists.
- The shell suite is now 10 tests; the contract suite remains 7.

Verification:

- App build: passed.
- UI tests: **17/17 passed** (7 contract + 10 shell), including the new
  deep-link test and the existing live-record/save and route-start flows.
- Phase 2 screenshot set: 13 screens.
- Phase 1 → Phase 2 Home comparison confirms the Quick Access move and the
  functional hero.

## Inventory delta

| Metric | Phase 1 | Phase 2 |
|---|---:|---:|
| Fixed `.font(.system(size:))` | 0 | **0** |
| Dynamic-Type font call sites | 472 | **476** |
| `String(format:)` calls | 41 | **41** |
| `PulseScreenHeader` compatibility usages | 5 | **3** |
| `RevertScreenHeader` compatibility usages | 12 | 12 |
| Distinct base sizes | 33 | 33 |

## Remaining

- **Phase 3:** cockpit HUD; D2-A (motorcycle-first lean hero) still needs to be
  applied.
- **Phase 4:** History/Insights/Summary data merge and chart fixes.
- **Phase 5:** Garage/Posters/Settings/Onboarding, AX-size audit, the Plan
  close-button polish, and the pre-existing unit-test discovery gap.
- Home still exposes the cockpit tile in Quick Access even though the Ride tab
  exists. It is useful as a shortcut and not harmful; revisit if the grid feels
  redundant after Phase 5.
- Settings is now reached through the palette button; the “More” menu holds
  Offline maps and Ride Lab. If the palette reads as “appearance only”, Phase 5
  can add a text “Settings” row without restoring the old duplicate menu.
