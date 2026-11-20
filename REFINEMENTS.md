# Refinements — the 264-item backlog

Everything in this file is a change to something **already shipped**. No new
features. Evidence was taken from the tree on 16 Nov 2026 (counts, line numbers,
and file sizes in the notes).

**How to use it**

- One checkbox per item. Tick it when the change is merged and verified, not when
  it is written.
- Effort tags: **Q** under half a day, **M** one to three days, **L** a week or
  more.
- The rule: **three items per week, quick wins first, and nothing new starts in an
  area where a checkbox is open.** A 264-item list is only useful if it shrinks.
- Items are grouped by kind, not priority. Priority is the `Start here` section at
  the bottom.

---

## 1. Architecture (1–10)

- [ ] **1.** Split `RideView` — 2,762 lines, 47 `@State`, 31 `onChange`, 32 helper funcs. (L)
- [ ] **2.** One preferences store — 50 `@AppStorage` keys plus 62 direct `UserDefaults.standard` calls. (M)
- [ ] **3.** Error policy instead of 300 `try?` — log once, show once. (M)
- [ ] **4.** Task lifecycle for 111 unstructured `Task {` — ownership and cancellation. (M)
- [ ] **5.** Presentation router — 35 `.sheet`, 30 `NavigationStack`; nested stacks and duplicated dismissals follow from this. (M)
- [ ] **6.** Split `revert/` into folders — 137 files in one directory. (Q)
- [ ] **7.** Decide `FeatureHubView` — 1,409 lines reachable from Home. (M)
- [ ] **8.** Retire Director mode — ~1,400 lines behind a debug flag. (Q)
- [ ] **9.** Central `DebugFlags` — 30 `#if DEBUG` blocks. (Q)
- [ ] **10.** Kill the renderer picker in the ride menu; auto-select by availability. (Q)

## 2. Design system (11–16)

- [ ] **11.** Colour tokens — 63 `Color(red:)` outside `RevertPalette`, plus hardcoded `SIMD4` in the renderer. (M)
- [ ] **12.** Typography tokens — 57 fixed `.system(size:)` calls. (M)
- [ ] **13.** Icon audit — 262 `Image(systemName:)`, inconsistent sizes and weights. (M)
- [ ] **14.** Unify cards, chips and banners — several bespoke variants. (M)
- [ ] **15.** One dark-mode policy — 21 `preferredColorScheme` calls. (Q)
- [ ] **16.** Map chrome parity across the three renderers — card and pill differ. (M)

## 3. Ride experience (17–24)

- [ ] **17.** Small-phone pass — SE width, the car HUD and card overlap. (M)
- [ ] **18.** Reduce Motion coverage — 11 references, map and camera paths incomplete. (Q)
- [ ] **19.** Haptic vocabulary — define tap, turn, arrive once. (Q)
- [ ] **20.** Audio ducking across voice, companion and music. (M)
- [ ] **21.** Battery mode ignores the new surfaces — weather, companion, Live Activity. (M)
- [ ] **22.** Offline preflight ties into PMTiles regions. (M)
- [ ] **23.** Cockpit exits — four ways to leave a ride, no consistent confirmation. (Q)
- [ ] **24.** Countdown and lap notices overlap the card on small screens. (Q)

## 4. Planning (25–31)

- [ ] **25.** `PlanView` is 2,121 lines with 32 `@State` — progressive disclosure. (L)
- [ ] **26.** Trips — reorder, edit and delete a day; currently append-only. (M)
- [ ] **27.** Loop deck empty and loading states. (Q)
- [ ] **28.** Route links — untrusted payload handling and expiry. (M)
- [ ] **29.** GPX import — progress, failure copy, duplicate detection. (M)
- [ ] **30.** Range ring — stale fuel data needs an age label. (Q)
- [ ] **31.** Conditions — offline and quota-exhausted states. (Q)

## 5. Data (32–37)

- [ ] **32.** `VersionedSchema` and `SchemaMigrationPlan` — none today. (M)
- [ ] **33.** Backup and export of rides, bikes and setups. (M)
- [x] **34.** Region manager — download, size, delete. (M)
- [ ] **35.** Undo for destructive actions — seven "Done" buttons, no undo trail. (M)
- [x] **36.** Duplicate rides after import. (Q)
- [ ] **37.** Fetch limits on the heavy `@Query` screens. (Q)

## 6. Companion (38–41)

- [ ] **38.** Off-switch discoverability test — On / Asked only / Off. (Q)
- [ ] **39.** Canned-line coverage report — which tiers actually have lines. (Q)
- [x] **40.** Fallback UX when the on-device model is unavailable. (M)
- [ ] **41.** "Forget everything" — confirmation and what it deletes. (Q)

## 7. Platform (42–47)

- [x] **42.** Widget and Live Activity staleness after a crash. (M)
- [x] **43.** CarPlay handoff when Organic Maps is missing or its mute resets. (Q)
- [ ] **44.** Siri intents — failure copy and the no-route case. (Q)
- [ ] **45.** Notification policy for service due and the monthly recap. (M)
- [ ] **46.** iPad layout — still iPhone-width optimised. (L)
- [ ] **47.** Privacy disclosure for weather coordinates and shared links. (Q)

## 8. Quality (48–52)

- [ ] **48.** Snapshot tests for the ride screen, car landscape and map chrome. (M)
- [ ] **49.** UI tests for the companion off switch and the car handoff. (M)
- [ ] **50.** Budget test in CI — cold start, first frame, ride FPS. (L)
- [ ] **51.** Surface the existing crash reports in Debug. (Q)
- [x] **52.** CHANGELOG says "Unreleased" while the app says 1.0. (Q)

## 9. Accessibility and inclusion (53–62)

- [ ] **53.** `ContentUnavailableView` for empty states — zero in the app. (Q)
- [ ] **54.** Dynamic Type sweep — one `dynamicTypeSize` modifier against 57 fixed sizes. (M)
- [ ] **55.** Accessibility hints — five for 137 files. (M)
- [x] **56.** `accessibilityValue` on gauges — lean, speed and ETA should announce numbers. (Q)
- [ ] **57.** VoiceOver actions for ride controls — pause, resume, end. (M)
- [ ] **58.** Increase Contrast and Reduce Transparency — 21 forced dark schemes need both checked. (M)
- [x] **59.** 44 pt hit-target audit — 31 `contentShape` calls, some chips smaller. (Q)
- [x] **60.** Map annotations need VoiceOver — puck, hazards and ghost are invisible. (M)
- [ ] **61.** Colour-blind check on route cyan versus hazard amber. (Q)
- [ ] **62.** Car landscape HUD at AX sizes — never sized up. (M)

## 10. Feedback and state (63–72)

- [ ] **63.** Skeleton loading — zero `redacted(`, 18 `ProgressView`; tiles, weather and posters flash empty. (M)
- [x] **64.** Determinate progress for downloads — regions, packs, offline prep. (Q)
- [ ] **65.** Error-copy tone guide — some messages apologise, some shout, some are debug strings. (Q)
- [ ] **66.** One banner component — `AlertBanner` plus the newer chips is two systems. (M)
- [ ] **67.** Undo for destructive actions — zero `UndoManager` uses. (M)
- [x] **68.** Search empty state — "no results" is indistinguishable from "still searching". (Q)
- [x] **69.** Retry affordances on network failures. (Q)
- [x] **70.** Haptics consolidation — 149 `RevertHaptics` calls, 14 raw ones bypass them. (Q)
- [ ] **71.** Turn-approach sound cue before a maneuver. (Q)
- [x] **72.** Import progress and cancel — GPX import has no way out. (M)

## 11. Search and planning depth (73–80)

- [ ] **74.** Saved-route organisation — folders, rename, sort; flat list today. (M)
- [ ] **75.** Trip export — days can be built but not shared as a bundle. (M)
- [x] **76.** Route rename inline — the title comes from the destination. (Q)
- [x] **77.** Alternative comparison — "slower but 40 % more curves" is the pitch, not shown. (M)
- [x] **78.** Reroute explanation — say why once when the route changes. (Q)
- [ ] **79.** Skip-waypoint affordance mid-ride. (Q)
- [ ] **80.** Merge an imported GPX into a saved route instead of a sibling. (M)

## 12. Data and integrity (81–88)

- [ ] **81.** Store growth control — tracks live in external storage and never compact. (M)
- [x] **82.** Track quantisation — six decimals and full timestamps per point is generous. (Q)
- [x] **83.** Hazard dedupe — the same closure reported twice shows twice. (Q)
- [x] **84.** Hazard TTL — rider marks never expire. (Q)
- [ ] **85.** Weather staleness label — a 40-minute-old forecast looks current. (Q)
- [x] **86.** PMTiles integrity check — a truncated region fails as a blank map. (Q)
- [x] **87.** Crash-report retention — the debug folder grows without a cap. (Q)
- [x] **88.** Debug archive size cap before share. (Q)

## 13. Platform and lifecycle (89–96)

- [ ] **89.** Background task budget — one `beginBackgroundTask` reference; exports and packs can be killed. (M)
- [ ] **90.** Widget timeline budget — audit against the daily allowance. (M)
- [x] **91.** Deep links cover four hosts — no `ride`, `history` or `companion`. (Q)
- [ ] **92.** Notification permission timing — after the first saved route, not at launch. (Q)
- [x] **93.** Idle-timer policy on cockpit versus map. (Q)
- [x] **94.** Thermal-state indicator, debug-only, so silent degradation is visible. (Q)
- [x] **95.** Screen-lock behaviour for the companion — verify no mic session survives. (Q)
- [ ] **96.** Restore-state on relaunch — reopen the last ride screen, not Home. (M)

## 14. Process and tooling (97–104)

- [x] **97.** Formatter and linter — no SwiftLint or SwiftFormat config in the repo. (Q)
- [x] **98.** File-length budget in CI — `RideView` at 2,762 lines happened because nothing objected. (Q)
- [ ] **99.** Test naming and layout conventions — 28 unit files, three styles. (Q)
- [ ] **100.** CI device matrix — one simulator; add SE-class and iPad. (M)
- [ ] **101.** Snapshot baselines in `.screens` — 178 entries with no diff gate. (M)
- [x] **102.** Docs link checker — four dead references appeared in one week. (Q)
- [x] **103.** Licences screen — OSM credited, SPM dependencies not. (Q)
- [x] **104.** Release checklist script — fold budget checks into `verify.sh`. (Q)

## 15. App size and assets (105–112)

- [ ] **105.** `BikeSprites.xcassets` is 93 MB — ~500 image sets shipped on every device. (L)
- [ ] **106.** Prune the sprite catalogue — most riders use one bike. (M)
- [ ] **107.** Move bike art to on-demand downloads or a compact atlas. (L)
- [ ] **108.** Sprite decode cost — 500 PNGs cost index time and memory pressure. (M)
- [ ] **109.** Audit `Assets 2.xcassets` for unused images after the redesign. (Q)
- [x] **110.** Check for 3D leftovers (`Meshes3D`, `Turntables`) no longer in the app. (Q)
- [ ] **111.** App thinning — no on-demand resources configured. (M)
- [ ] **112.** Startup asset index — measure launch with the sprite catalogue installed. (Q)

## 16. Content and catalogues (113–122)

- [ ] **113.** Bike catalogue 500+ entries generated; years and categories unvalidated. (M)
- [ ] **114.** Voice-pack catalogue — 188 entries, 94 dead links; regenerate with the availability scan. (Q)
- [ ] **115.** Voice-pack attribution and licence status in About. (Q)
- [ ] **116.** Community pack index — no way for riders to add their own source. (M)
- [ ] **117.** Hazard seed data freshness and regional coverage. (M)
- [ ] **118.** Speed-limit coverage — no way to see where data is missing. (M)
- [x] **119.** Elevation cache — 90-day expiry, no size cap. (Q)
- [ ] **120.** Fuel data source — Overpass query cost and failure copy. (M)
- [ ] **121.** Curated road data — no editorial layer beyond OSM tags. (L)
- [ ] **122.** Poster themes — six palettes, no previews for light and dark. (Q)

## 17. Edge cases and failure modes (123–136)

- [x] **123.** Location denied mid-ride — what the cockpit shows. (M)
- [x] **124.** GPS loss — puck freezes with no "searching" state. (M)
- [ ] **125.** Bluetooth helmet disconnect — audio fallback and a spoken notice. (M)
- [ ] **126.** Low storage during a long ride — journal writes fail silently. (M)
- [x] **127.** Timezone or DST change mid-ride — elapsed and ETA clocks. (Q)
- [x] **128.** Unit switch mid-ride — affects recorded stats. (Q)
- [ ] **129.** Airplane mode — tiles, weather and companion degrade into one coherent state. (M)
- [x] **130.** Phone call interruption — does the ride keep recording? (Q)
- [ ] **131.** Rotation and split-screen — iPad and CarPlay mirrors. (M)
- [ ] **132.** Background audio conflict — music versus companion versus navigation. (M)
- [x] **133.** Thermal throttling feedback — silent today. (Q)
- [x] **134.** Battery below 20 % — nothing changes; the ladder should. (Q)
- [ ] **135.** Empty or single-point route — export, ring and ribbon guards. (Q)
- [ ] **136.** Duplicate ride after crash recovery. (Q)

## 18. Build and CI (137–144)

- [x] **137.** CI comment says iOS 26, project targets 18.0 — drift in the first file a contributor reads. (Q)
- [ ] **138.** CI runs one simulator — add an SE-class and an iPad run. (M)
- [ ] **139.** No scheduled/nightly CI run — regressions surface only on pull requests. (Q)
- [ ] **140.** No SPM dependency cache in CI — every run recompiles the renderer. (M)
- [ ] **141.** Build time — measure a clean build and cache it. (M)
- [x] **142.** `.build-*` directories litter the repo root; confirm ignored and clean. (Q)
- [ ] **143.** Test parallelisation and retries — UI tests are the flaky ones. (M)
- [ ] **144.** No coverage report in CI. (Q)

## 19. Store, legal and docs (145–154)

- [x] **145.** Privacy policy URL — About explains data locally but links no policy. (Q)
- [x] **146.** Terms of use — none. (Q)
- [x] **147.** Licences screen — SPM dependencies are not credited. (Q)
- [x] **148.** Attribution completeness — OSM ODbL, ImmersiveMap MIT, bundled tiles. (Q)
- [ ] **149.** App Store screenshots and GIFs — none generated. (M)
- [x] **150.** Support URL and contact channel. (Q)
- [ ] **151.** Changelog automation — hand-maintained and drifting. (M)
- [ ] **152.** README screenshots — `.screens` holds 178 frames, the README shows none. (Q)
- [x] **153.** Contributor guide — issue templates exist, a build-and-test page does not. (Q)
- [x] **154.** README feature list versus reality — sixteen features added, list unchanged. (Q)

## 20. Per-screen polish (155–178)

- [ ] **155.** Home — the hero shows the last ride; "next" (planned loop, conditions) should be primary. (M)
- [ ] **156.** Home — quick actions are text chips; unify with the map dock vocabulary. (Q)
- [ ] **157.** Plan — 2,121 lines, 32 `@State`; split into destination, loops and settings stages. (L)
- [ ] **158.** Plan — the conditions strip sits below the fold on an SE. (Q)
- [ ] **159.** Plan — range ring and fuel stops disagree when the tank is edited mid-plan. (Q)
- [ ] **160.** Plan — no recent destinations section despite search history existing. (Q)
- [ ] **161.** Route builder — alternatives computed, never compared side by side. (M)
- [ ] **162.** Saved routes — flat list; needs folders, sort and a map preview per row. (M)
- [x] **163.** Loop deck — no empty state when the planner returns nothing. (Q)
- [ ] **164.** Sprint planner — no explanation of how a sprint is scored. (Q)
- [ ] **165.** Trip planner — no drag-to-reorder for days. (M)
- [ ] **166.** Trip planner — no per-day map preview. (M)
- [ ] **167.** History — filters exist, no search by road name. (M)
- [x] **168.** History — no bulk delete. (Q)
- [ ] **169.** Ride summary — the corner report is a separate screen; link it inline. (Q)
- [ ] **170.** Corner report — no "compare to last attempt" despite route keys existing. (M)
- [ ] **171.** Poster — PNG only; no story or wide aspect variants. (Q)
- [ ] **172.** Rivals — no merge when two devices derive the same route key differently. (M)
- [ ] **173.** Segments — no map preview or delete for detected segments. (M)
- [ ] **174.** Garage — bike art dominates; specs and service are below the fold. (M)
- [ ] **175.** Bike editor — 500+ catalogue entries in a picker with no search. (M)
- [ ] **176.** Maintenance — no "mark done" shortcut from the due banner. (Q)
- [ ] **177.** Voice packs — the browser lists dead packs; filter by availability by default. (Q)
- [ ] **178.** Settings — eight sections, no search, no reset, no "what changed". (M)

## 21. Per-module code health (179–192)

- [ ] **179.** `NavigationManager` — 1,035 lines; reroute, guidance and state in one type. (L)
- [ ] **180.** `RoutePlanner` — 1,806 lines; extract cache keying and fallbacks. (L)
- [ ] **181.** `RouteBuilder` — 1,261 lines; preference plumbing repeats through four call sites. (M)
- [ ] **182.** `TwistyLoopEngine` — settings plumbed by parameter; introduce a profile value. (M)
- [ ] **183.** `RoadStore` — 1,018 lines mixing cache keys, decoding and queries. (M)
- [ ] **184.** `GraphCache` — eviction policy undocumented and untested at the boundary. (M)
- [ ] **185.** `HazardStore` — curated data and rider marks share one store; split by provenance. (M)
- [ ] **186.** `ElevationService` — no cancellation on route change. (Q)
- [ ] **187.** `FuelService` — corridor radius is a magic number in three places. (Q)
- [x] **188.** `LocationHub` — lease model is good; document the invariants. (Q)
- [x] **189.** `RideRecorder` — suspend and resume paths need a state diagram in comments. (Q)
- [ ] **190.** `Speaker` — one queue for clips and speech; the companion adds a third source. (M)
- [x] **191.** `WidgetBridge` — snapshot writing has no schema version. (Q)
- [x] **192.** `LiveRideActivity` — update throttling implicit; make the budget explicit. (M)

## 22. Test gaps (193–204)

- [x] **193.** `RouteRibbon` — no test for the travelled/remaining split. (Q)
- [x] **194.** `MapConfig` — no test that renderer settings are stable across launches. (Q)
- [x] **195.** Weather parsing — no fixture test for the Open-Meteo or MET Norway payloads. (M)
- [x] **196.** Region handling — no test for a truncated or missing PMTiles file. (M)
- [ ] **197.** Migration — no test that an old store opens after a schema change. (M)
- [x] **198.** GPX fuzz — malformed, huge and coordinate-bomb files. (M)
- [x] **199.** Link decoder fuzz — untrusted `revert://` payloads. (M)
- [ ] **200.** Performance — no test asserting solve or frame budgets. (M)
- [ ] **201.** Car landscape snapshot — the new HUD has no baseline. (Q)
- [x] **202.** Companion off-switch UI test — On / Asked only / Off persistence. (Q)
- [ ] **203.** Accessibility UI test — extend `AccessibilityContractUITests` to four new screens. (M)
- [ ] **204.** Offline end-to-end — a UI test with the network disabled. (M)

## 23. Device and platform matrix (205–216)

- [ ] **205.** iPhone SE (3rd gen) — cockpit card, dock and ETA pill at 375 pt. (M)
- [ ] **206.** iPhone 16 Pro Max — Dynamic Island and Live Activity alongside the cockpit. (Q)
- [ ] **207.** iPad mini / Air — split view, rotation and sheet detents. (M)
- [ ] **208.** CarPlay 1920×720 versus 800×480 — the car HUD assumes one aspect. (M)
- [ ] **209.** Motorcycle head unit (Chigee/Carpuride class) — touch targets and glare. (M)
- [ ] **210.** Landscape phone in a mount — `carLandscape` is car-only; riders mount sideways. (M)
- [ ] **211.** External display and Stage Manager — nothing verified. (Q)
- [ ] **212.** Display Zoom — layouts at 320 pt effective width. (Q)
- [ ] **213.** Bold Text — custom-font labels do not respond. (Q)
- [ ] **214.** Large Content Viewer for map dock icons. (Q)
- [ ] **215.** VisionOS target — declared in `TARGETED_DEVICE_FAMILY`, never verified. (Q)
- [ ] **216.** Older device class (A12) — 120 fps target needs a sane fallback. (M)

## 24. Permissions (217–224)

- [x] **217.** Location "While Using" only — background warning exists; copy and recovery need review. (M)
- [x] **218.** Precise location off — routes degrade; say so before the ride. (M)
- [x] **219.** Motion & Fitness denied — lean and g-force silently zero. (Q)
- [x] **220.** Microphone denied — what the rider is told. (Q)
- [x] **221.** Speech recognition denied — verify the path. (Q)
- [ ] **222.** Bluetooth denied — helmet audio and remote fall back silently. (Q)
- [ ] **223.** Notifications denied — service due and recap have no channel. (Q)
- [ ] **224.** Files access for GPX import — document picker versus shared container. (Q)

## 25. Network and failure matrix (225–236)

- [ ] **225.** Offline from the start — tiles, weather, companion, search. (M)
- [x] **226.** High latency (500 ms+) — timeouts and retry copy. (Q)
- [ ] **227.** Captive portal — weather returns HTML; parser behaviour. (Q)
- [x] **228.** DNS versus TLS failure — distinguishable errors. (Q)
- [ ] **229.** HTTP 429 — weather quota exhausted; fall back to sun-only. (Q)
- [x] **230.** HTTP 500 — retry with backoff, not on every plan. (Q)
- [x] **231.** Malformed or truncated JSON — no crash, one warning. (Q)
- [ ] **232.** Tile 404 inside a region — a hole, not a blank screen. (Q)
- [x] **233.** Overpass timeout — hazard load fails; does the ride still start? (Q)
- [ ] **234.** PMTiles read error mid-ride — degrade to the MapKit renderer. (M)
- [ ] **235.** Airplane mode toggled mid-ride — tiles cached, weather stale, companion quiet. (Q)
- [x] **236.** Slow disk under storage pressure — journal writes and crash reports. (Q)

## 26. Data model, per entity (237–248)

- [ ] **237.** `Ride` — validation on import; zero-distance and single-point rides. (M)
- [ ] **238.** `RidePoint` — null lean, null time, out-of-order timestamps. (Q)
- [ ] **239.** `Bike` — delete cascades to maintenance and setups. (Q)
- [ ] **240.** `MaintenanceEntry` — due-date versus due-distance conflicts. (Q)
- [ ] **241.** `SetupNote` — delete with its bike; confirm first. (Q)
- [ ] **242.** `SavedRoute` — duplicate detection and rename collisions. (Q)
- [ ] **243.** `SavedPlace` — Home and Work deletion semantics. (Q)
- [ ] **244.** `Trip` and `TripDay` — cascade both ways; orphan days. (M)
- [ ] **245.** `UserHazard` — TTL, dedupe and delete from the map. (Q)
- [ ] **246.** `Segment` — delete when its ride is deleted. (Q)
- [ ] **247.** Voice-pack metadata — reinstall after an app update. (Q)
- [ ] **248.** Every entity — export shape and a round-trip test. (M)

## 27. State machines (249–256)

- [ ] **249.** Ride lifecycle — start, pause, background, suspend, recover, end. (M)
- [ ] **250.** Navigation session — preview, active, reroute, arrived, cancelled. (M)
- [ ] **251.** Companion — on, asked-only, off, unavailable-model, listening. (M)
- [ ] **252.** Weather — idle, loading, ready, stale, unavailable. (Q)
- [ ] **253.** Tile region — absent, downloading, ready, corrupt, evicted. (M)
- [ ] **254.** Import — picking, parsing, previewing, saving, failed. (Q)
- [ ] **255.** Export — preparing, sharing, cancelled, failed. (Q)
- [ ] **256.** Handoff — available, exported, muted, returned. (Q)

## 28. Time and calendar (257–264)

- [x] **257.** DST spring forward — a 2 a.m. ride and elapsed clocks. (Q)
- [x] **258.** DST fall back — the duplicated hour in history. (Q)
- [ ] **259.** Timezone travel — a trip across zones mid-day. (Q)
- [x] **260.** Midnight boundary — "today" in Home and the monthly recap. (Q)
- [x] **261.** Leap day — recap and anniversaries. (Q)
- [ ] **262.** 24-hour versus 12-hour — every `formatted` call. (Q)
- [x] **264.** Clock change during a live ride — ETA and elapsed. (Q)

---

## Start here

**Week 1** — 2 (preferences store), 11 (colour tokens), 53 (empty states).
**Week 2** — 12 (typography), 15 (dark-mode policy), 67 (undo).
**Week 3** — 19 (haptics), 68 (search empty state), 105 (sprite size, spike only).
**Week 4** — 32 (schema plan), 48 (snapshots), 137 (CI drift).

Then take one **L** per month — 1 (`RideView`), 25 (`PlanView`), 105/107 (assets),
179 (`NavigationManager`) — and keep the weeks otherwise short.

## Notes

- Counts and sizes are from 16 Nov 2026 and will drift; re-verify with
  `grep`/`wc` before quoting an item as still true.
- Items marked (L) should not start without the previous week's checkboxes closed.
- If an item is wrong or already fixed, delete the line rather than leaving it
  ticked; a stale list is worse than a short one.
