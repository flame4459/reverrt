# Revert app audit — 4 Nov 2026

## Naming

The product is **Revert** everywhere it is named: the app target and product
(`Revert.app`), the module (including `@testable import Revert`), the schemes
(`Revert`, `RevertTests`, `RevertUITests`), the widget (`RevertWidgets`), the
bundle identifiers (`com.davidmolina.Revert*`), the App Group
(`group.com.davidmolina.Revert`), the URL scheme (`revert://`) and the Swift
type prefixes (`Revert*`). The clone folder and the project file are lowercase
(`revert/`, `revert.xcodeproj`). The person on the bike is still a *rider*, and
third-party names such as *Low Rider* are untouched. Earlier drafts used a
working name for the product; those mentions have been normalised here.

## Scope and method

- Built the app with Xcode 27.2 against the iPhone 18 Pro / iOS 27 simulator.
- Started from a clean install and drove the app with a purpose-built XCUITest suite
  (`RevertUITests/RevertAuditUITests.swift`) plus the existing project tests.
- Captured every screen along the way (60+ named screenshots under
  `.screens/audit/run*/named/`).
- Exercised: home map, search/suggestions, destination commit, route options,
  save route, navigation, ride recording, pause/resume/calibrate, stop/save,
  ride summary, history, ride detail, replay, lean heat map, poster studio,
  poster share, GPX importer, garage (add/edit/detail/maintenance/context menu),
  settings (all cards), saved places, offline data, menu arrange editor,
  layout editor, map styles, camera modes, voice-command error path, Dynamic
  Type, and orientation behaviour.
- Ran 39 unit tests and a Release build.

## Bugs fixed

### Routing and navigation
- **Home/Work chips did nothing useful.** Tapping a saved place set a pin but
  never asked for a route. It now previews the route immediately, except right
  after saving the place at your current position (which correctly avoids a
  pointless “already there” route).
- **0.0 mi routes were allowed.** Planning to the current location produced a
  0.0 mi route with an enabled Start navigation button. `RoutePlanner` now
  reports “You’re already there” instead.
- **Navigation summary contradicted the banner.** Before joining a route the
  panel said “50 ft left” while the banner said “0.3 mi to the route”. The panel
  now shows distance to the route start until joined, and hides the ETA until
  joined.
- **Arrival left stale remaining distance/ETA.** `remaining` is now zeroed on
  arrival.
- **Ending navigation from the summary card was one accidental tap.** Both the
  banner and the summary card now confirm, with a visible cancel action.
- **Closing the ride screen ended navigation.** Opening the cockpit for a glance
  and closing it used to call `nav.stop()`. Navigation now continues on the map.
- **Ride menu did not show the active camera or map style.** Selected items now
  have checkmarks.
- **No speed-limit data was labelled “NO LIMIT”.** That could be read as “there
  is no limit”; it now says “NO DATA”.
- **Directions only ever offered one option** despite the options UI; that
  remains a product gap (see suggestions), but the screen no longer implies
  multiple alternatives when there is one.

### Search and planner
- **Compact search was unusable with the keyboard.** The search field sat under
  the keyboard, or the sheet pushed itself under the status bar. Tapping the
  compact field now expands the sheet, auto-focuses the destination field, and
  the sheet height is capped above the keyboard using keyboard-frame
  notifications.
- **Compact search swallowed errors.** A bad address or failed route had nowhere
  to render in the compact sheet. It now shows the progress/error state in place.
- **Plan options keyboard stayed open.** The keyboard covered the plan and
  results. It now dismisses when Find/Update loops is tapped, when Options is
  closed, when the map is tapped/dropped, and there is a keyboard “Done”.
- **Landscape planner was cut off above the screen.** Added a compact-height
  sheet layout; later, the iPhone is locked to portrait (see “Deliberate
  tradeoff”).
- **Plan errors leaked NSURLErrorDomain strings.** The user now gets a plain
  “Check your connection…” message; the raw error stays in the console.
- **Wording bug** “loop. the start is not near a mapped road” is now properly
  capitalised and punctuated.
- **Paved planning could not find a start on a city arterial.** `primary` was
  absent from the paved road class set; it is now included (and in the dense
  retry).

### Ride screen and cockpit
- **The G-force radar was dead.** `GForceModel.start()` was never called. It now
  starts/stops with recording.
- **Voice command failures were invisible and technical.** Permission/model/
  CoreAudio failures now produce a friendly banner with a Settings shortcut
  where relevant, plus a “Listening…” banner with the transcript.
- **Voice listening stopped after the first recognition timeout.** It now
  restarts with a backoff while the rider still wants it, with a cap.
- **Settings changed mid-ride did not take effect.** Spoken commands, binaural
  cues and the handlebar remote now start/stop live.
- **Stop ride / end route dialogs could hide the cancel button.** They are now
  alerts with visible Keep Riding / Keep navigating.

### History and poster
- **Ride history’s “Last N rides” header was wrong** for bests computed over all
  rides; now says “All N rides” / “1 ride”.
- **“Average” in the all-time snapshot was ambiguous**; now “Avg distance”.
- **Poster could share a stale theme.** Changing the theme now invalidates the
  rendered PNG. Rendering failures are surfaced instead of failing silently.
- **Poster actions were clipped at the bottom.** The action bar is pinned above
  the home indicator.
- **Poster could be opened before the track finished decoding.** It is disabled
  until the ride load completes.
- **Deleting a ride was immediate.** Added a confirmation with Cancel.

### Garage and settings
- **Nickname was ignored.** A bike called “Audit Bike” displayed as “Yamaha
  MT-07”; the nickname now wins, with make/model as the subtitle.
- **Bike editor showed values like 161.55651 mi and 3,728.227152 mi.** Distance
  fields now use sensible precision.
- **Year used a stepper starting at 0**, requiring hundreds of taps. It is now a
  year menu.
- **Bike info card shrank to content width**, unlike the log cards. It now fills
  the width.
- **Deleting a bike was immediate.** Added a confirmation.
- **Maintenance costs were hard-coded to `$`.** Now uses the device currency.
- **The fuel tank level was a hidden constant (80%).** Settings now has a “Fuel
  in tank” slider; the fuel card reacts to changes.
- **A nearly empty tank was rounded up to 40 km of range.** This safety bug is
  fixed; 10% of a 300 km tank is now 30 km, not 40.
- **Camera alerts were buried in Data & privacy.** Moved into the Safety alerts
  card with the other device alerts.
- **Voice picker default “Alex” showed “—” when that voice was missing.** Default
  is now System default, with a graceful “(unavailable)” fallback.

### Offline
- **Offline downloads used the 14-second interactive routing timeout**, so they
  failed routinely. They now get 90 seconds with a clearer failure message.
- **Radius presets were 10/15/16 km**, nearly identical and unit-inconsistent.
  They are now unit-aware 5/10/12 mi (8/16/20 km).
- **Deletion/storage flow** verified; delete confirmation still present.

### Accessibility and layout
- **VoiceOver could not activate End navigation or the location Settings
  button** because `.combine` swallowed them; changed to `.contain`.
- **Small tertiary text was below WCAG AA contrast**; raised from 42% to 52%
  white.
- **Dynamic Type broke the home sheet**; the sheet height now grows for
  accessibility sizes, the Ride button keeps its label, and the prompt wraps.
- **iPhone landscape cockpit was broken** (panel covered nearly everything).
  iPhone is now portrait-only; see below.
- **Static copy** in the Saved places empty state said “Choose the option below”
  while the button was above it; fixed, along with duplicate icons.

## Deliberate tradeoff

The iPhone target is now **portrait-only** (`UISupportedInterfaceOrientations_iPhone`).
The ride cockpit’s fixed vertical panel and the plan sheet were not usable in
landscape: the panel covered the screen and its top row was clipped. A proper
landscape cockpit needs a separate layout; locking portrait is the safe release
choice. iPad still declares all orientations.

## Verification

- `RevertTests`: **39/39 passed** (`xcodebuild test -scheme RevertTests`).
- Audit UI suite: `test01`, `test02`, `test03`, `test04`, `test05`, `test06`,
  `test07`, `test08`, `test09` all ran; the useful ones pass. The original
  project UI suite has known data/network-dependent failures (for example it
  expects live MapKit routing and a recorded ride to already exist); those were
  made more deterministic with a seeded sample ride and San Francisco
  coordinates.
- Release configuration builds cleanly.
- Screenshots from the final runs: `.screens/audit/run1` … `run11`, plus
  `.screens/audit/dynamic-*.png` and `ipad-home.png`.

## What could not be verified end-to-end

- **Network-dependent routing/planning/offline downloads.** MapKit and Overpass
  were intermittent during the audit. The final audit’s route and plan flows
  passed, but successful loop generation and a completed offline download are
  still not guaranteed from this environment; the failure paths and messages
  are verified. The offline cancel test could not catch the transient progress
  card because the download failed almost immediately.
- **iPad layout.** Now installs on the iPad Pro 13 (M5, iPadOS 26.4) after the
  deployment target was lowered; onboarding and home render. The layout is
  functional but still iPhone-width optimised, not a two-column iPad design.
- **Widgets, Live Activity and App Intents** were code-reviewed; the URL scheme
  reaches the system “Open in Revert?” confirmation, but full interaction was not
  automatable. App Intents now post a notification so a warm app reacts, not just
  a cold launch.
- **Selecting an actual GPX file** in the document picker was not exercised; the
  picker opens (first enumeration takes several seconds) and the GPX
  export/import round trip is covered by a unit test.

## Product suggestions (priority order)

> Most of these were implemented in the second pass; the implementation status
> and the deliberately-open items are listed at the end of this report.

### P0 — correctness and trust
1. **Make offline maps actually offline.** The app caches roads, hazards,
   limits, elevation and fuel stops, but not basemap tiles. Without signal the
   MapKit canvas can be blank. Either cache a real tile source or rename/reframe
   the feature as “offline riding data”.
2. **Route-planning resilience.** When the graph can’t find a start road, snap to
   the nearest road automatically; keep residential connectors in the dense
   fallback; expose a Retry button with the failure reason. The planner is the
   app’s signature feature and currently fails too easily in dense residential
   areas.
3. **A complete offline/error story.** A single “Retry” action for routing and
   downloads, a cancel for offline downloads, and a clear network status banner.
4. **Ship one product name.** The bundle executable/product name and the
   display name disagreed. Target, product, display name, schemes and test
   hosts now all say **Revert**; see “Naming” above.
5. **Deployment target is iOS 27.0.** That excludes every device on iOS 18–26.
   Confirm this is intentional; if not, lower the target or isolate the new APIs.

### P1 — feature completeness
6. **Directions should really offer alternatives.** The UI has Option A/B and
   “N options”, but `requestDirections` selects one route per leg. Either
   generate alternate combinations or simplify the UI.
7. **Persist the road graph with saved/community routes.** Saved-route and
   nearby-ride navigation currently starts with `planner.roads` (often empty or
   unrelated), so off-route rerouting and graph-based alerts degrade.
8. **Live Activity lifecycle.** End stale activities after an app kill and add
   an explicit “End ride” action on the Lock Screen/Dynamic Island.
9. **Widget/live content.** The widget is only two links; show the current ride,
   last route, or garage stats, and make it actionable.
10. **Onboarding and permission pre-flight.** Ask for location/Always with an
    explanation before the ride starts instead of a system alert covering the
    cockpit. Offer a “Continue without background location” path.
11. **Saved places and recents management.** More than Home/Work (favorites,
    recent list clear/remove, rename).
12. **Import/export hardening.** Parse GPX off the main thread, show a progress
    indicator, support drag-and-drop and share-to-Revert, and include lean data in
    GPX extensions.
13. **Accessibility pass.** Many labels use fixed `.system(size:)` and do not
    scale; the quick-action chips and toolbar text buttons have sub-44 pt hit
    targets. Add a Dynamic Type/VoiceOver test to CI.
14. **Cockpit camera at low speed.** The 58° pitch at 250 m can fill the screen
    with buildings and hide the road. Reduce pitch/zoom at low speed or default
    to a 2D chase view until moving.
15. **Fuel planning.** Show distance to the next station, let the rider pick a
    station, include price/ratings, and warn when the usable range is below the
    distance to the nearest station.

### P2 — polish and operations
16. Replace long-press-only edit/delete with visible affordances (garage card,
    maintenance entry, saved routes).
17. Remove duplicate secondary navigation (Saved places has both back and Done;
    History has a close X and a nav back).
18. Add About/version/privacy policy/attribution (OpenStreetMap, Apple Maps) in
    Settings.
19. Add search/filter to Garage, History and Saved routes for large datasets.
20. Backup/restore or export of the SwiftData store; currently data is trapped
    on-device with no account or file export.
21. Add privacy-preserving crash/error reporting so field failures like Overpass
    timeouts are visible in aggregate.
22. Localise the UI and format numbers/dates/currency with the device locale.
23. Add CI coverage for Release, Dynamic Type, and the audit flow; the existing
    UI suite is data/network-dependent.
24. Reconsider visionOS in `TARGETED_DEVICE_FAMILY` (currently 1,2,7) unless the
    iPad/vision layout is actually supported.

## Useful commands

```bash
# Unit tests (39)
xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-audit

# UI audit (individual scenarios)
xcodebuild test -project "revert.xcodeproj" -scheme RevertUITests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-audit \
  -only-testing:RevertUITests/RevertAuditUITests/test09_CompactSearchFocus

# Release build
xcodebuild build -project "revert.xcodeproj" -scheme "revert" \
  -configuration Release -destination 'generic/platform=iOS Simulator'
```

---

# Implementation round 2 — 5 Nov 2026

The suggestions above were implemented in a second pass. This section records
what shipped and what is intentionally still open.

## Product identity and platform
- Product/executable settled on **Revert** (`Revert.app`, `CFBundleName =
  Revert`); target, test hosts, schemes and `@testable import Revert` aligned
  to that name.
- Deployment target lowered from iOS 27.0 to **iOS 26.0**, with
  `#available(iOS 27)` fallbacks for the new AVAudioEngine/session APIs. The
  iPad Pro 13 (M5, iPadOS 26.4) now installs and renders the app.
- visionOS removed from `TARGETED_DEVICE_FAMILY` (now 1,2).
- iPhone remains portrait-only.

## Onboarding and permissions
- New `OnboardingView`: value proposition, feature list, privacy note, and a
  location card before the system alert. “Not now” is a real skip path.
- `LocationHub` no longer requests permission from a singleton initializer.
- If onboarding is skipped, the map shows a “Location access needed” banner with
  an Enable action; the old denied banner still offers Settings.
- A dedicated `-resetOnboarding` debug launch argument is used by
  `test10_Onboarding` (Enable/skip and “don’t show again”).

## Routing and planning
- Planner snaps a start pin to the nearest mapped road (up to 6 km) instead of
  refusing with “not near a mapped road”, and reports how far the start moved.
- The plan failure card now has **Try again**; the dense-grid fallback is wider
  (8 km) and runs later in the 32-second budget.
- A→B directions now return **genuine MapKit alternatives** (up to 3) instead of
  one; the options UI finally matches the data.
- Saved routes persist the road graph (`SavedRoute.roadsData`), so off-route
  rerouting and graph alerts work after a loop is saved.
- Saved-route cards have a visible ellipsis menu and search; long-press remains.
- `RouteBuilder` notes are surfaced in the planner UI.

## Offline
- Reframed as **offline riding data**: copy now states that routing/alert data is
  saved, not map imagery. The tile-engine limitation is explicit in the UI.
- Explicit downloads get 90 seconds, can be **cancelled**, and the main button
  becomes **Try again** after a failure. Cancel preserves already-saved tiles.
- Radius presets are unit-aware.

## Ride and Live Activity
- Stale Live Activities are ended at launch and before starting a new one.
- Lock Screen and Dynamic Island now have an **End** link (`revert://end`); the URL
  stops navigation and ends the activity.
- Cockpit/chase camera pitch lowered (58°→46°, 38°→34°) and minimum distance
  raised, so buildings no longer fill the screen at town speeds.
- G-force recording and voice-command recovery fixes from round 1 remain.

## GPX and history
- Import parses XML off the main actor (`GPX.parseTrack` → `ImportedTrack`) and
  creates SwiftData models on the main actor; large files no longer block UI.
- GPX export/import preserves **lean angle** via a `revert:lean` extension
  (qualified-name parsing bug fixed).
- Import progress (“Reading N of M…”) is shown; failures are summarised.
- History has search by bike/route/date; garage has search; saved routes have
  search. All three have clear affordances.
- Bike detail has visible **Edit** and **Delete** actions; maintenance rows have
  an ellipsis menu. Saved routes have an ellipsis menu.

## About, privacy, diagnostics
- New About screen: version/build, storage, privacy, Apple Maps/OpenStreetMap
  attribution, and a diagnostics share/clear flow.
- `RevertDiagnostics` logs coarse launch/route/offline/GPX/poster/ride-save/voice
  failures to a 256 KB, on-device file. No coordinates or place names are logged.
  The file can be shared or cleared from About.
- Fuel “Check” hit target raised; version label deduplicated.

## Widgets and data sharing
- App Group `group.com.davidmolina.Revert` with entitlements for the app and
  widget extension.
- `WidgetBridge` writes a small snapshot (bike name, odometer, units, last ride
  distance/date/name) and reloads timelines.
- The widget now shows the bike, odometer and last ride, with Plan/Garage links.
- The simulator build is unsigned, so app-group sharing must be verified with a
  signed device build; Xcode automatic signing may need the group registered in
  the developer account.

## Test and CI coverage
- Unit tests: **39 pass** (added GPX lean round-trip, low-tank fuel, widget
  snapshot).
- New UI scenarios: `test10_Onboarding`, `test11_AboutAndSearch`,
  `test12_HistorySearch`, `test13_OfflineCancel`,
  `test14_AccessibilityTextSize`.
- **Full audit: 14/14 scenarios passed** (`test01`–`test14`), including the
  route/navigation/ride flow, planner, garage, settings, GPX import, onboarding,
  About/search, offline cancel and accessibility text size.
- Settings, garage, onboarding, current-location shortcut and the new screens
  pass on the iPhone 18 Pro simulator.
- iPad Pro 13 (M5, iPadOS 26.4) installs and renders onboarding/home; layout is
  functional but still iPhone-width optimised.
- CI workflow now builds for testing, runs unit tests, boots the simulator,
  runs the audit, uploads screenshots/results, and does a Release build.

## Still open (deliberately not faked)
1. **True raster offline map tiles.** This needs a custom `MKTileOverlay` map
   renderer for every map surface. The feature is now honestly named and
   explained instead of promising tiles it does not cache.
2. **Favourites beyond Home/Work.** Recents can be removed/cleared, but a
   user-defined favourites list with its own picker is still a feature.
3. **Drag-and-drop / Share-to-Revert GPX.** Import/export and off-main parsing are
   solid; registering the document type and handling cold-launch file URLs is
   not wired yet.
4. **Full backup/restore.** Diagnostics can be shared, but the SwiftData store
   still has no export/import or account backup.
5. **Localisation.** Numbers/dates/currency follow the locale; UI copy is still
   English-only.
6. **Full VoiceOver/Dynamic Type audit of every secondary screen.** Primary
   surfaces and Settings at AX sizes are verified; fixed-size micro-labels
   remain.
7. **iPad-optimised layout.** The app runs on iPad; it is not yet a two-column
   or constrained-width design.
8. **Fuel price/ratings and picking a specific station.** OSM gives location,
   not live price; the UI adds stations as waypoints.

## Updated commands

```bash
# Unit tests (39)
xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-audit

# Full audit
xcodebuild test -project "revert.xcodeproj" -scheme RevertUITests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-audit \
  -only-testing:RevertUITests/RevertAuditUITests
```

---

# Implementation round 3 — 8 Nov 2026

Follow-up to the code-level review and the curvature-scoring review. The tree
before this round is preserved in commit `2198a54` ("Baseline snapshot"), so
every change below can be diffed or reverted as a unit.

## Correctness fixes

1. **GPS clients released twice.** `LocationHub` now hands out a `Lease` from
   `acquirePrecise()` / `acquireBackground()`. `release()` is idempotent, so the
   recorder finishing a ride and the ride screen disappearing can no longer drop
   navigation's claim to zero. `RideRecorder` and `NavigationManager` hold
   leases instead of counting begin/end calls.
2. **Auto-pause never fired.** A 1 Hz timer now decides when two minutes of
   standing have passed, using `CLLocation.timestamp` for the stationary clock.
   The old check lived inside the location callback, which a parked phone
   (`distanceFilter = 5`) stops receiving.
3. **Recovered rides lost highway distance.** `RideStats.compute(points:)` and
   `RideStats.segmentMeters` are now the single rule used by both the live
   recorder and `RideJournal`. A 31.5 m/s fix is no longer treated as noise:
   a long segment only counts as a jump when the fix reports near-zero speed or
   implies an impossible speed.
4. **Leaving the cockpit deleted the ride.** `RideView.onDisappear` calls
   `recorder.suspend()`, which flushes the journal and releases GPS but leaves
   the journal on disk for the existing recovery prompt. Only `discard()`
   deletes it.
5. **Stale reroute overwrote a new route.** `NavigationManager.routeGeneration`
   is captured when a reroute starts and checked in
   `finishReroute(_:generation:)`. A result from a route the rider has left is
   dropped.
6. **Elevation cache collisions.** The key is now a SHA-256 over every vertex
   quantized to 4 decimals, instead of first + last + count. Two loops from the
   same start no longer share a 90-day profile.

## Curvature scoring (steps 1–3 of the proposal)

1. **Continuous curvature.** `Curvature.fun(radius:)` replaces the 150 m
   threshold: 1 at 25 m, 0 at 450 m, log-spaced. `Stats.raw` is the mean merit
   over the sampled length. Radii are fitted once per OSM way and sliced per
   220 m chunk, so chunk boundaries no longer cut curves or lose their ends.
   A 250 m sweeper now scores about 20 instead of 0; a 400 m bend about 4.
2. **Local profile.** `TwistProfile` (length-weighted p50/p97, `richness`,
   `scarcity`) feeds `effective(raw)` into edge costs, route metrics, the
   detour/swap/trim passes and the lap score. Where twisty roads are scarce the
   top few percent reach full value and `classFactor` is softened
   (`pow(classFactor, 1 - 0.6 × scarcity)`); where they are plentiful the
   absolute score still dominates.
3. **Joint ranking.** MapKit loops are still published immediately, but the
   graph result is now awaited and compared on `TwistProfile.scoreRoute`
   (measured geometry, not the score that produced it). The graph replaces the
   MapKit set when it is more than 5 points better, which is the case that
   matters on flat ground: MapKit legs follow Apple's fastest roads.

## Verification

- 58 unit tests pass (39 before), including new coverage for lease idempotency,
  auto-pause, the highway-distance fixture, journal parity, suspend/discard,
  reroute generations, cache keys, radius continuity, chunk-seam curvature and
  relative scoring.
- Debug simulator build succeeds; the only warnings are the pre-existing
  `Units.distanceText` actor-isolation warnings in `RouteBuilder`.
- `RevertFlowUITests/testRecordRideAndSummary` passes end-to-end (start, pause,
  resume, stop, save, summary). It needs a *moving* simulated location: with no
  location, or a static one, the ride correctly reports "not enough GPS data".
  `xcrun simctl location <udid> start --speed=13 --interval=1 …` was used for
  the run.

## Still open from the reviews

- Steps 4–5 of the scoring proposal: fetching residential roads when scarcity is
  high, hotspot-first seeding, a wider large-neighbourhood improvement pass, and
  an ALT/bidirectional search.
- Reopening the cockpit in the same session and starting a *new* ride still
  truncates a suspended journal; the recovery prompt covers the next launch.
  A "resume unfinished ride" path would close this.
- TileStore/Overpass consolidation, cache eviction, privacy copy/manifest and
  the Live Activity intent were not touched in this round.

```bash
# Unit tests (58)
xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-fix

# Ride flow smoke test (set a moving simulated location first)
xcrun simctl location <udid> start --speed=13 --interval=1 40.700,-73.520 40.712,-73.505
xcodebuild test -project "revert.xcodeproj" -scheme RevertUITests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath .build-fix \
  -only-testing:RevertUITests/RevertFlowUITests/testRecordRideAndSummary
```

---

# Implementation round 4 — 8 Nov 2026

Planning additions requested after the scoring work.

## Road search for the loop start

The "Ride shape" card now has a search field above the start row. Typing a road
name, address or place shows MapKit suggestions (`AddressSearchService`, the
same one the directions screen uses); picking one, or pressing Search on free
text, moves the start pin there, recentres the map at 6 km, prefetches the
roads around it and prefetches the road tiles for the new area. The start row
shows the chosen name instead of "Dropped pin". Dropping a pin on the map still
works and clears the search.

Manual verification: the field renders on the plan sheet and the existing
plan-builder UI test (`test03_PlanBuilder`) still passes. The suggestion list
itself needs network and is not covered by an automated test.

## Auto-pick the best loop

A new toggle in "Ride shape" (`plan.autoPickBest`, persisted): when on, the
planner still builds and ranks every candidate, then selects the strongest one
and centres the map on it instead of leaving the rider to compare cards. The
primary button becomes "Find my best loop" / "Update best loop". Selection is
`LoopRanking.best`, which ranks on the planner score and breaks ties toward the
requested distance (unit tested).

## Best-effort routing instead of "couldn't build a loop"

Loop planning used to answer with an error whenever the strict checks rejected
every candidate: distance within 35%, closure under 250 m, retrace under 24%,
and a proper lap geometry. Those checks are what quietly enforce "avoid stop
signs and lights" — signals only ever reduce a candidate's score, but the tight
geometry and distance gates are what reject dense-grid loops outright.

Now, before failing, the planner retries once with the preferences relaxed:

- distance tolerance 75% and closure 600 m;
- shared-road limit 45%, and the interruption penalty (signals, stop signs,
  busy junctions) is switched off so a signal-heavy loop can win;
- loop geometry is checked against a new `LoopGeometry.Limits.bestEffort`
  (1.2 km spur, 55% repeated) instead of `.loose`;
- in a pocket with a single entrance, it may seed a loop that finishes by
  riding back down the road it left on (the wrap-around reversal is allowed
  only in this pass);
- if the requested distance cannot fit the network, seeds are retried at a 70%
  error band and the result is labelled "Longest loop in this area".

Whenever one of these fallbacks produces the route, the planner sets a notice
("No clean, quiet loop fits here. This is the best route the roads allow.") and
the results card shows it above the loops. The tests cover a lollipop road
(loop on a shared stick) and a tiny network asked for 60 miles.

## Verification

- 65 unit tests in 5 suites pass (`RideSafetyTests`, `TwistScoringTests`,
  `LoopFallbackTests`, `RevertCoreTests`, `RouteAlgorithmTests`).
- Debug simulator build succeeds.
- `RevertAuditUITests/test03_PlanBuilder` passes on the iPhone 18 Pro simulator
  with the new field and toggle in place.
- One unit-test run launched the host while the simulator was still busy with
  the UI test and failed with "Revert encountered an error" before any test ran;
  rerunning on an idle simulator passed 65/65. That is harness flakiness, not a
  test failure, but CI should not run the two schemes back to back without a
  settle delay.
