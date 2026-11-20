# Revert — feature outline

Planning pass, 14 Nov 2026. **Status: first integrated pass implemented** —
entry points, data models and limitations are described in the README’s
“Ride Lab” section. The outline remains the place to argue about scope.

Scope: the sixteen features agreed after the two brainstorm rounds, minus four
that were explicitly dropped (§10).

Refinements to what already shipped are tracked separately, one checkbox each:
[REFINEMENTS.md](REFINEMENTS.md) (264 items, three per week).

---

## 1. Ground rules

Every feature below has to live inside the promises the README already makes.
Where a feature wants to break one, the outline says so instead of quietly
assuming a backend.

| Rule | Consequence |
| --- | --- |
| No accounts, no analytics, no server of ours | Anything social travels inside a link, a QR code or AirDrop. Nothing needs a login. |
| Everything on the phone | Weather is the one exception: a keyless forecast API (Open-Meteo) called directly from the device, no account. |
| SwiftUI + SwiftData, iOS 17.4, no dependencies | New data goes into the existing store with defaults so old stores keep opening. |
| One store shared by app, widgets, Live Activity, CarPlay | New models must be reachable from the widget and CarPlay processes without duplicating logic. |
| The cockpit is used with gloves, in wind, at speed | New in-ride interactions are voice, haptic or single large targets. No new small buttons. |

---

## 2. The three bets

The first round of ideas sorted itself into three bets, and the ordering in §6
follows them.

1. **The plan should feel aware.** It currently knows roads, fuel and curvature
   but not the weather, the light, the bike's range or whether the ride will
   work offline. Conditions, range ring, offline preflight, touring.
2. **The ride should be hands-free and repeatable.** Voice-marking, ghost chase,
   long-ride battery mode, ride-again. The cockpit is the only place a rider
   can learn something new about their own preferences, and right now the app
   learns nothing there.
3. **The data should mean something afterwards.** Corner report, monthly log,
   service history, segment hunt, loop deck. Today a ride is a row and a GPX;
   it should be a record of a road you now know.

---

## 3. A · Planning

### A1. Conditions on the plan card

**Problem.** A motorcycle ride is planned around weather and daylight, and the
app is blind to both. A perfect twisty loop at 4 p.m. in November is a wet-leaf,
low-sun, deer-o'clock loop.

**Shape.** On the plan card and the loop cards, a one-line conditions strip:
departure window, temperature, precipitation chance, wind, sunset. Expanding it
shows hour-by-hour for the next six hours, with the planned ride duration
shaded over the timeline. Warnings are plain sentences, not icons:
"wet roads likely after 16:00", "sunset 17:02 — you'd finish in the dark",
"6 °C at 900 m on the ridge".

**Data.** No new persisted model in v1 — the forecast is fetched per plan and
cached for ~15 minutes. `ConditionsService.snapshot` (already in
`FeatureCore.swift`, sun-only today) grows a `RideConditions` value type: window,
hourly samples, sun times, warnings. If the plan is saved, persist a compact
snapshot so the saved route still explains itself later.

**Source: no Apple entitlement.** WeatherKit is dropped — it needs a paid Apple
Developer Program membership and an App ID capability, and the app is not going
there. Three keyless providers instead, behind one protocol:

| Provider | Role | Notes |
| --- | --- | --- |
| **Open-Meteo** | Primary forecast | No key. 48 h hourly. Takes several coordinates in one call, so a whole loop is one request. Free for non-commercial use; attribute "Weather data by Open-Meteo.com" (CC-BY 4.0) |
| **MET Norway** | Fallback forecast | No key. Global. Requires a descriptive `User-Agent` with contact — a generic one returns 403 — and results must be cached |
| **NWS** | Severe-weather alerts, US | No key. `api.weather.gov/alerts/active?point=…`, used for warnings only, not forecasting |

Request shape (Open-Meteo), sampled at start, thirds and end of the route plus
its highest point:

```
/v1/forecast?latitude=a,b,c&longitude=x,y,z
 &hourly=temperature_2m,precipitation_probability,precipitation,
         wind_speed_10m,wind_gusts_10m,visibility,dew_point_2m
 &timezone=auto&forecast_days=2
```

Field mapping into `RideConditions`:

| Ride need | Open-Meteo field |
| --- | --- |
| Temperature, and the ridge drop | `temperature_2m` per sample point |
| "Wet roads likely" | `precipitation_probability` + `precipitation` |
| Wind and gusts | `wind_speed_10m`, `wind_gusts_10m` |
| Fog | `dew_point_2m` within 2 °C of `temperature_2m` |
| Low sun / visibility | `visibility` (m) plus the existing on-device sun times |

Warning thresholds, one table, tuned per region later: gusts > 40 km/h; precip
probability > 50 % inside the ride window; precipitation > 1 mm/h; visibility
< 2 km; temperature < 5 °C; dew-point spread < 2 °C; sunset inside the ride
duration. Each maps to one plain sentence, never an icon alone.

The sun maths stays on-device so an offline plan still gets daylight warnings;
a failed fetch degrades to sun-only rather than blocking the plan.

**Touches.** `FeatureCore.swift` (`ConditionsService`, `RideConditions`), new
`WeatherProviders.swift` (protocol, Open-Meteo, MET Norway, NWS), `PlanView`
plan card, `TwistyLoopEngine`/`LoopRanking` plumbing, `SettingsView` toggle,
`AboutView` for the attribution and the coordinates-leave-the-device line.

**Depends on.** Nothing.

**Risk.** Three providers means three failure modes; keep them behind one
protocol and cache per rounded coordinate cell (~15 min) so a plan screen cannot
hammer anyone's free tier. Rural sample points are coarse. Coordinates now go to
a third party — say so in the privacy copy. Riders in California and Scotland
need different warning thresholds.

**Smallest slice.** Temperature + rain chance + sunset for the plan card only,
no hourly view, no elevation nuance.

**Effort.** M.

---

### A2. Range ring and turn-back line

**Problem.** "Can I get there and back on this tank?" is a pre-ride question
every rider asks, and the app answers it only after a route exists
(`FuelService.plan`).

**Shape.** On the map, a faint ring at `tank range × 0.9` with a labelled
"turn back here" boundary, computed from the active bike's tank and observed
consumption (fall back to a per-bike default). Fuel stations inside the ring are
tinted; stations outside are dimmed. Tapping a station shows distance and
whether it is reachable with a 15% reserve. The plan card gains
"fits your range: yes / tight / no".

**Data.** Bike gains `tankLitres`, `observedConsumption` (km/L, rolling), and
`reserveFraction` with sensible defaults; `RangePolicy` computes the ring and
the verdict. Fuel stations already come from `FuelService`.

**Touches.** `Vehicle.swift` (or `Garage.swift` bike fields), `FuelService`,
`MapUI.swift`, `PlanView`, `Garage` editor, `DebugScreens` for a simulated
bike.

**Depends on.** A1 only for the "wind and hills cost range" nudge (v2).

**Risk.** Consumption estimates are noisy in the first tank; show a range, not
a number, until three rides are recorded.

**Smallest slice.** Static ring from the bike's declared tank and a fixed
consumption figure, drawn on the plan map.

**Effort.** M.

---

### A3. Touring mode

**Problem.** The app plans one ride. A weekend away is four rides, a place to
sleep and a way to get the bike home, and the current answer is "export four
GPXs and use another app".

**Shape.** A trip is an ordered list of days. Each day has a start, an end, a
distance target and a loop-or-point-to-point choice; overnight stops are saved
places. The trip view shows a day strip, totals per day, fuel stops per day and
a "fits the daylight" check per day (uses A1). Export is one GPX per day or one
combined file. No change to the shake-down of the ride itself: a trip day
launches the normal cockpit.

**Data.** New `Trip` and `TripDay` SwiftData models (title, dates, ordered
days, notes), pointing at `SavedRoute` for the generated geometry. Days own
their own settings snapshot so editing the trip does not silently rewrite a
route already ridden.

**Touches.** New `TripPlannerView` + `TripDetailView`, `RoutePlanner` entry
point that accepts a trip day, `SavedRoutesView` to file days under a trip,
`GPX` export loop.

**Depends on.** A2 (range per day) is useful but not required; A1 for daylight.

**Risk.** Scope. A trip planner that also books hotels is a different product;
keep it to routing and logistics notes.

**Smallest slice.** Two days, no notes, GPX per day.

**Effort.** L.

---

### A4. Swipeable loop deck

**Problem.** "Where do I go tonight" is a decision problem, and a list of ranked
loops is a worse answer than five cards.

**Shape.** A deck of five nearby loops, each a poster-style card (distance,
time, curve count, best profile) with a tiny map thumbnail. Swipe left to drop,
right to keep; keeping opens the normal plan sheet with the loop selected.
"Surprise me" reshuffles. The deck is a Pulse sheet, reachable from home and
from the plan screen.

**Data.** None new: `LoopRanking.best` already ranks candidates and
`PulsePostersView`/`StoryPoster` already render poster art. The deck needs a
session-local list so a reshuffle does not repeat a card.

**Touches.** New `LoopDeckView`, `PulseHomeView` entry, `PlanView` handoff,
`LoopRanking` (a "diversity" pass so the five cards are not the same road).

**Depends on.** A1 to badge "good light tonight".

**Risk.** Card generation is slow if it calls the planner five times; generate
candidates in one planner pass and slice.

**Smallest slice.** Deck with static thumbnails, no diversity pass.

**Effort.** M.

---

### A5. Import from other planners

**Problem.** Riders arrive with routes built in Kurviger, Calimoto or Rever.
GPX import exists but imports a *track*, not the intent, so the app cannot
re-plan or reroute along it.

**Shape.** Import detects common planner GPX conventions (waypoint naming,
`<wpt>` vs `<trkpt>`, route vs track) and offers: "ride this track as-is"
(today's behaviour) or "re-plan these waypoints with Revert" (snap the
waypoints to roads and run the normal planner with the rider's preferences).
Import maps `Avoid motorways` / `curvy` hints into a one-off
`RoadPreferences` for that plan only.

**Data.** `ImportedTrack` gains waypoints and an importer enum;
`RoutePlanner` gains a "re-plan from waypoints" entry. Preferences stay
transient unless the rider saves them.

**Touches.** `GPX.swift`, `HistoryView` import sheet, new import review screen,
`RouteBuilder`.

**Depends on.** None; benefits from route links (A6) if a link arrives instead
of a file.

**Risk.** Every planner's GPX dialect is a little different; keep parsing
defensive and show what was understood before planning.

**Smallest slice.** Read `<wpt>` and re-plan them; ignore the hints.

**Effort.** M.

---

### A6. Serverless route links

**Problem.** Sharing a ride today means a GPX file or a screenshot. Sharing a
*plan* — the loop you want your friend to ride on Sunday — has no format.

**Shape.** A `revert://route` link carrying a compact route description:
rounded waypoints (5 decimals), loop settings, name, and a mode byte. The same
"fits in a messaging app" budget as `SharedRideReplay` (~1.6 kB), so
iMessage does not truncate it. Opening the link previews the route, then
"ride it" or "save it". A QR code is offered for meetups, generated from the
same payload.

**Data.** New `RouteLink` codec (versioned, like `RideTrackCodec`), a
`RouteLinkPreview` model in the open-URL path. `RivalLink.host` handling in
`RevertApp.swift` shows the pattern to follow; route links must not collide
with rival links.

**Touches.** New `RouteLink.swift`, `RevertApp.onOpenURL`, `PlanView` share
button, `SavedRoutesView`, `Info.plist` URL types, `SharedRideReplay` for the
encoding budget.

**Depends on.** Route identity (already `RouteFingerprint`) so a link and a
subsequent ride can be compared.

**Risk.** URL schemes are a public contract; version the payload from day one
and keep an unknown-version fallback that asks the user to update.

**Smallest slice.** Encode, decode, preview, ride. No QR yet.

**Effort.** M.

---

### A7. Per-ride offline preflight ("Pack this ride")

**Problem.** The offline story is a global setting with a known hole (no
basemap tiles). Riders cannot tell whether *this* ride is covered.

**Shape.** One action on the plan card: pack the corridor. It caches roads,
hazards, limits and elevation for the loop's bounding box (already available
through `RegionPrep`/`RegionCoverage`) and reports a checklist:
"roads ✓ hazards ✓ limits ✓ map imagery — limited offline". A green/amber/red
badge appears on the plan and later on the ride screen. Packing shows progress,
can be cancelled, and can be scoped by radius.

**Data.** Existing tile stores (`RoadStore`, `TileStore`, `HazardStore`,
`ElevationService`) plus a `PackManifest` recording what was packed for which
route and when, stored per `SavedRoute`.

**Touches.** New `RidePackService`, `RegionPrep`, `PlanView`, `OfflineView`,
`SavedRoutesView`, `DebugScreens`.

**Depends on.** A6 (a pack travels with a shared link? v2).

**Risk.** Packing a long corridor can be heavy; cap radius and show bytes
before starting.

**Smallest slice.** Pack on demand for the plan's corridor with a three-line
checklist, no per-route persistence.

**Effort.** M.

---

## 4. B · In the saddle

### B1. Voice-marked hazards and roads

**Problem.** Road debris, a washed-out corner, a road you never want again — the
only moment you know this is while riding, and the app gives you no hands-free
way to record it.

**Shape.** Two commands added to the fixed vocabulary: "mark hazard" (drops a
pin at the current fix, with an optional "gravel / oil / animal / police" tail)
and "avoid this road" (adds the current road name to `RoadPreferences.avoided`).
Both are confirmed by a short spoken acknowledgement, and both are listed for
review after the ride so a misheard command is easy to undo.

**Data.** `HazardStore` gains a user-hazard layer (timestamp, coordinate, kind,
severity) separate from curated data; `RoadPreferences` gains a persisted
`avoided` set with the road it came from and when.

**Touches.** `VoiceCommandRecognizer` (enum + phrase table), `HazardStore`,
`RoadPreferences` + `RoadPreferencesView`, `RouteHazardLoader`,
`RideDebugView` for review, `Speaker` for confirmations.

**Depends on.** None.

**Risk.** False positives from wind noise; make undo one tap and never let a
single "avoid" permanently blacklist a road.

**Smallest slice.** "Mark hazard" with a fixed kind, reviewed in History.

**Effort.** M.

---

### B2. Ghost chase

**Problem.** `SharedRideReplay` can replay a friend's ride, and Rivals can rank
results, but neither is usable *during* a ride. There is no way to race your own
best lap.

**Shape.** When the rider starts a route that already has a rival result or a
previous attempt, the map can show a ghost marker moving along the recorded
track at the recorded pace, with a live delta ("+2.4 s"), sector splits every
third, and an end-of-ride summary of where the time went. Ghost is opt-in per
ride; audio cues stay minimal.

**Data.** None new — `RideTrackCodec` encoding, `Ride.routeKey`, and
`RidePoint.elapsed` cover it. A `GhostSession` value type interpolates position
from elapsed time.

**Touches.** `SharedRideReplay`, `RideView`/`MapUI` overlay,
`NavigationManager` (elapsed clock aligned to the ghost), `RideSummaryView`
sector table, `RouteLeaderboardView` "chase this" entry.

**Depends on.** B-phase prerequisites: a consistent per-route start alignment
(start line = first ghost point, snapped).

**Risk.** Safety. A rider chasing a delta will ride faster than they intended.
Default to a muted delta (splits only), and never show a "you're behind" nag in
the cockpit more than once per sector.

**Smallest slice.** Ghost marker + single overall delta, own best only.

**Effort.** M.

---

### B3. Long-ride battery mode

**Problem.** There is no battery or thermal handling in the target. A four-hour
day with the screen lit and GPS at full rate ends with a dead phone, and the app
does not warn or adapt.

**Shape.** A "long ride" switch on the ride screen (and an automatic suggestion
when the planned duration exceeds three hours). It dims or blanks the screen
between turns, lowers the location rate when the route is straight, keeps the
next turn in the Live Activity, and shows a "projected battery at finish" line
before starting. It never turns navigation off; it degrades the presentation.

**Data.** No persisted model; a `RidePowerPolicy` value type with the tiers,
plus a `RideEfficiencyLog` for debugging (rate changes, screen state) in the
debug folder.

**Touches.** `RideView`, `LocationHub`, `IdleTimer`, `LiveRideActivity`,
`RevertServices`/`NavigationManager`, `PulseDesign` (dim layer), `SettingsView`.

**Depends on.** None.

**Risk.** Blanking the screen looks like a bug; the dimmed state needs one
obvious tap-to-wake affordance and a spoken "screen dimmed" on first use.

**Smallest slice.** Manual toggle that dims after 10 s at speed and restores on
tap; no GPS-rate change.

**Effort.** M.

---

### B4. Ride it again

**Problem.** Rides are rows in a journal. There is no affordance anywhere to
ride a loop a second time, even though `Ride.routeKey` already groups them.

**Shape.** A confirmed ride gets a "ride again" action in History and in the
summary. It reloads the same route and the same settings into the plan screen
with one tap. Rides that share a `routeKey` collapse into one entry with an
attempt count and bests (time, lap, lean, smoothness), which is also the natural
home for ghost chase and segments.

**Data.** `Ride.savedRouteID` already exists; add `Ride.routeKey` use in the
history query and a `RouteAttempt` grouping view model. No schema change.

**Touches.** `HistoryView`, `RideSummaryView`, `Models.swift` (`routeKey` is
present but only used by Rivals), `SavedRoutesView`, `PlanView` preload path.

**Depends on.** None, but unlocks B2 and C4.

**Risk.** Re-planning can produce a different route than the one ridden; store
the ridden geometry with the route so "again" is exact.

**Smallest slice.** "Ride again" button that preloads the plan; no grouping.

**Effort.** S.

---

## 5. C · After the ride

### C1. Corner report

**Problem.** The app records lean, speed and a curvature field, then reduces it
to averages. The interesting part — what happened in each corner — is thrown
away.

**Shape.** A per-ride screen: corners detected from the road geometry and the
track, each with entry/apex/exit speed, max lean, and any mid-corner braking or
lean spike. The headline is one "smoothness" score with a short sentence about
the pattern ("you were quickest in the first half, then braked mid-corner in the
last three"). No grade letters, no leaderboard of corner speed.

**Data.** Derived only: `RidePoint` (speed, lean, time) snapped to road
geometry via the existing `CurvatureField`/`RoadGraph` chunking. A cached
`CornerReport` on `Ride` (external storage) so it is computed once.

**Touches.** New `CornerReport.swift`, `RideAnalysis`, `TwistProfile`,
`RideSummaryView` new section, `RideDebugView`.

**Depends on.** B4 for the "same corner, next attempt" comparison.

**Risk.** Privacy and tone: a per-corner speed record is sensitive and invites
risk-taking. Default off, opt-in per ride, no absolute speeds shared in posters.

**Smallest slice.** Corner list with max lean and a smoothness number; no
coaching sentence.

**Effort.** L.

---

### C2. Monthly ride log poster

**Problem.** `StoryPoster` is a strong sharing surface, but only for a single
ride. The accumulated story — the month — has no artefact.

**Shape.** On the first of the month (and on demand), a poster with miles,
rides, longest day, roads ridden twice, best corner, lean record, fuel stops,
and one line of prose. Reuses the existing themes and type system; the layout is
a new template, not a new design language.

**Data.** A `MonthlyRecap` computed from `Ride`/`RideJournal`; no new storage
beyond an optional "last generated" stamp so the prompt appears once.

**Touches.** `StoryPoster`, `PulsePostersView`, `HistoryView` entry,
`RideJournal`, notifications (`RevertNotifications`).

**Depends on.** None; richer with C1.

**Risk.** The social-media gaze can make riders chase numbers. Keep the copy
about places and roads, not speed records.

**Smallest slice.** Poster view with the numbers, no notification and no prose.

**Effort.** S.

---

### C3. Service and setup history per bike

**Problem.** `Bike` and `MaintenanceEntry` exist, but there is no service
interval logic, no setup notes, and no link between what was done to the bike
and how the rides felt.

**Shape.** Per bike: mileage-based reminders (chain, oil, tyres, brake fluid)
computed from the odometer, a tyre-pressure log, and setup notes with tags
("touring", "track day") and suspension/tyre values. A ride can be tagged with
a setup, so history can be filtered by it. A "due soon" row appears on the
garage card, not as a push notification by default.

**Data.** `Bike` gains odometer and interval settings; `MaintenanceEntry` gains
kind, due-mileage and notes; new `SetupNote` model; `Ride` gains optional
`setupNoteID`.

**Touches.** `Garage.swift` (`Bike`, `MaintenanceEntry`, editor views),
`Models.swift`, `HistoryView` filter, `PulseHomeView` garage card.

**Depends on.** None.

**Risk.** Reminders on a hobby app become nagging; default to a quiet card and
let the rider opt into notifications.

**Smallest slice.** Intervals and a due-soon badge; no setup notes.

**Effort.** M.

---

### C4. Segment hunt

**Problem.** `SprintPlannerView` plans sprints from a start point, but the
best stretches a rider discovers mid-ride cannot be kept, compared or shared.

**Shape.** After a ride, detect one-to-five-kilometre twisty stretches from
curvature and distance, name them from the road (`StreetNames`), and keep local
bests. Riders can save a segment as a target ("ride this again, timed") or share
it as a link (A6). Local only; no global leaderboard without a server.

**Data.** New `Segment` model (geometry simplified to ~20 points, name, length,
curvature summary, best effort reference). `Ride` gains a relationship to
segments found on it.

**Touches.** New `SegmentDetector.swift`, `Rivals`/`RideTrackCodec` reuse,
`TwistyLoopEngine` scoring utilities, `HistoryView`, `RideSummaryView`, map
overlay in `MapUI`.

**Depends on.** A6 for sharing; B4 for repeat attempts.

**Risk.** Segment detection over-triggers on every bend; require a minimum
continuous twistiness score and let the rider delete junk.

**Smallest slice.** Detect and list segments with length and curve count; no
timing, no sharing.

**Effort.** L.

---

## 6. D · Reach and platform

### D1. Shortcuts, Focus and widget

**Problem.** `RideIntents` exists but the app is not woven into the phone:
no Siri phrase for a usual loop, no Riding Focus behaviour, a widget that shows
two links.

**Shape.** "Hey Siri, start my usual loop" (last or most-ridden route),
a Riding Focus that suppresses non-ride notifications and starts the cockpit
stripped down, and a widget that shows the best loop for right now with a
one-tap start. App Intents get the same route/segment vocabulary as `plan`,
`garage`, `end`, `drive`.

**Data.** None new; intents resolve against `SavedRoute` and `Ride.routeKey`.

**Touches.** `RideIntents.swift`, `RevertWidgets`, `WidgetBridge`,
`RevertApp`, `SettingsView` (Focus toggle).

**Depends on.** B4 (usual loop), A1 (best loop for conditions).

**Risk.** Focus automation is invisible when it works and confusing when it
does not; make the toggle explicit and reversible.

**Smallest slice.** Siri intent + widget showing the last route.

**Effort.** M.

---

### D2. In-car handoff (no entitlement)

**Problem.** Riders want the planned route on the car screen, and Apple's
`com.apple.developer.carplay-maps` entitlement is not granted yet. The entitled
CarPlay app in `CarPlayRideCoordinator.swift` exists but cannot sign.

**Shape.** Revert keeps navigating and keeps talking; a free GPX app (Roavic)
draws the track on the head unit with its own voice off. One action, "Send to car
screen", writes a track-only GPX and opens the share sheet. Car-only scope — this
does not touch the bike cockpit.

**Data.** None new. A track-only GPX exporter variant (`<trk>`/`<trkseg>`, no
`<rte>`), synthetic `<time>` values, ≤50 m gaps, curve vertices preserved.

**Touches.** `CarHandoff.swift` (both exporters and the handoff sheet), plan
card/route preview/saved-route menu in `PlanView`, tests in
`RevertTests/CarHandoffTests.swift`.

**Depends on.** Nothing. Independent of the entitlement work.

**Risk.** Roavic is a one-person app with no API; the mute is a rider step.
Mitigation: the handoff is app-agnostic, so any GPX handler in the share sheet
works.

**Smallest slice.** Track-only export plus share sheet, with the reminder copy.

**Effort.** S. Implemented: `CarHandoff.swift`.

---

### D3. The companion (voice and personality)

**Problem.** Narration is a voice pack plus system TTS, and the system tier is
the compact one nobody downloaded. There is no character behind the voice, so
nothing in the app sounds like it has a point of view.

**Shape.** Tom (Enhanced) as the ship voice, pinned by name rather than "first
enhanced in the list", with a quality badge and a download hint in the picker.
On top: canned and templated lines that answer questions, make the odd dry
remark, and check in on a nine-minute budget — dry, brief, never during a
maneuver. A one-tap off switch (On / Asked only / Off) silences him without
touching navigation prompts. Free-form answers only on iOS 26 Foundation Models, and every fact
still comes from a tool. Tiers 0–1 ship without any model.

**Data.** New `CompanionScript`, `CompanionDirector`, `CompanionMemory`,
`CompanionTools`. No new server, no account, nothing leaves the device.

**Touches.** `Speaker.swift`, `VoicePickerView.swift`, `SettingsView.swift`,
`HandlebarRemote.swift`, `VoiceCommandRecognizer.swift`.

**Depends on.** A1 (conditions) for weather answers; B4 for "third time on this
loop"; `FuelService`, `HazardStore`, `RideJournal` for the rest.

**Risk.** A chatty companion at speed is a safety problem, and a model that
guesses facts is worse. Mitigation: the Director owns a hard speaking budget,
and Tier 2 answers must be tool-backed or refused.

**Smallest slice.** Pin Tom, label tiers, and ship Tier 0 lines only.

**Effort.** L. Implemented: `Companion.swift`, `CompanionLanguageModel.swift`,
`CompanionWeather.swift`.

**Status.** Tier 0/1, Tier 2 Foundation Models, Tom voice pinning, the
always-waiting “Hey Ace” wake word, Bluetooth/Cardo microphone preference,
hold-to-talk, state chip/remote/Settings and the on-device 20-episode memory are
built. The companion uses the keyless Open-Meteo reader; the planner’s full
weather card still needs the A1 provider UI. It refuses to invent conditions.

### D4. Map experience (the Google-Maps feel)

**Problem.** The ride map is a SwiftUI `Map` whose camera is animated through
state every 80 ms, overlays are rebuilt on every GPS tick, and the puck is raw
GPS. It works; it does not feel like Google Maps.

**Shape.** A camera engine (look-ahead, heading EMA, speed pitch, spring
interpolation on a display link), a route matcher so the puck sits on the road,
an `MKMapView` renderer behind a `MapRenderer` protocol, a ribbon with casing and
travelled/remaining split, a vector basemap styled by us (satellite is out), choreographed
transitions, tabular digits, and a chevron puck with a speed cone. Optional
later: a corridor road overlay drawn from `RoadStore`, ribbon shading by pace or
twistiness, and instant search.

**Data.** None new. Precomputed per-segment bearings and look-ahead tables at
plan time; `progress` (metres along the route) becomes the single source for
distance, ETA and camera.

**Touches.** `RideView.swift` (map view), `CockpitCamera.swift`, `MapUI.swift`,
new `RideCameraEngine`, `RouteMatcher`, `RouteRibbon`, `MapRenderer` +
`MapKitRenderer`, `MapConfig`, `NavBanner`/`RideView` chrome.

**Depends on.** Nothing hard. F13 (app-wide perceived performance) touches
startup and screen transitions, so it should land with it rather than after.

**Risk.** `MKMapView` inside SwiftUI needs discipline (no state writes from
`updateUIView`, gestures owned by the map). Satellite imagery is softer offline.
The corridor overlay is easy to make slower than the map it sits on.

**Smallest slice.** Camera engine + puck + tabular digits on the existing SwiftUI
map — a day, and already most of the perceived difference.

**Effort.** L. Implemented: `MapExperience.swift`, `ImmersiveMapRenderer.swift`,
`MapKitRenderer.swift`. Remaining smoothness work, the ranked fixes and the frame
targets: [MAP_SMOOTHNESS.md](MAP_SMOOTHNESS.md). Labels keep their own design:
[DECLUTTER.md](DECLUTTER.md).

---

## 7. Sequencing

| Phase | Features | Why this order |
| --- | --- | --- |
| 1 · Three weeks | A2 range ring · A1 conditions · B4 ride again · A6 route links · D2 in-car handoff | Each is small, each is independent, and together the plan screen stops feeling blind. B4 is the cheapest retention win in the list, and D2 gets the route onto a car screen without waiting for Apple. |
| 2 · In-ride | B1 voice marks · B3 battery mode · B2 ghost chase · D4 map experience | All three change what happens on the bike, share cockpit work, and depend on the ride screen being touched once, not three times. |
| 3 · Insight | C1 corner report · C2 monthly poster · C3 service history | Needs phase 2's ride data in place; corner report is the differentiator and should not be rushed. |
| 4 · Big shapes | A3 touring · C4 segments · A4 loop deck · A5 import · D1 shortcuts · D3 companion | Larger or more speculative; the earlier phases make them cheaper (route identity, links, attempts). |

Dependencies worth calling out:

- **Route identity** (already `RouteFingerprint` + `Ride.routeKey`) is the spine
  of B2, B4, C4 and A6. It is built but barely used; phase 1 should exercise it.
- **A6 route links** unlock A7 packing-travels-with-link, C4 sharing and the QR
  meetup idea. Build the codec once, versioned.
- **B4 ride again** is the precondition for "compare this attempt" everywhere.

---

## 8. Crosscutting work

Not features, but they decide whether the features feel finished.

- **One link format registry.** `revert://` currently has five hosts and two
  payload styles (`RivalLink`, `RideTrackCodec`). Add route and segment payloads
  with a shared version byte and a decoder that fails gracefully.
- **Settings surface.** Conditions, ghost, corner report, service reminders and
  Focus each add a toggle. One "Ride behaviour" section, grouped, not five new
  screens.
- **Privacy copy.** The weather provider, location exports and shared links all
  move data off-device in ways the About screen should explain in one paragraph
  each.
- **Accessibility.** New cards and the deck must survive Dynamic Type AX3; the
  deck is a good place to prove the `.system(size:)` cleanup landed.
- **Tests.** Planner invariants (range ring monotonicity, link round-trip,
  ghost interpolation, segment detection fixtures) belong in the existing unit
  suite; UI tests only for the start/again flows.

---

## 9. Decisions needed

1. **Weather provider** — confirm Open-Meteo as the default (no key, no
   entitlement) with MET Norway as fallback, and decide who tunes the warning
   thresholds per region.
2. **Ghost default** — muted splits or full delta on first use? I would ship
   splits-only and let riders opt in.
3. **Corner report gating** — opt-in per ride, or on by default with speeds
   hidden until expanded?
4. **Touring scope** — is touring a 1.0 feature or a 1.1 headline?
5. **Segments** — local-only forever, or link-shared results (still no server)?
6. **Naming** — the "Pulse" language (PulseHome, PulsePosters, PulseSafety) is
   not in the README. Fold it into the product story or phase it out?

---

## 10. Out of scope (agreed)

| Dropped | Note |
| --- | --- |
| Watch companion | Revisit after battery mode; the haptic channel is still the right answer for gloves. |
| Time-budget knob | Excluded this round; `TwistyLoopSettings.maximumDurationSeconds` stays derived from length. |
| Tank-bag cue sheet / PDF | Excluded; the route link covers the sharing need for now. |
| iCloud sync | Excluded; the on-device promise stays literal. Backup remains the audit's open item. |

### Parked, not dropped

| Item | Status |
| --- | --- |
| Director mode (`RideDirectorReplayView`, `ReplayDirector`, `DirectorOverlays` — ~1,400 lines) | **Parked.** Debug-flag only and plays `DebugScreens.sampleRide()`, so no rider can reach it. Leave the files alone; do not spend 1.0 time finishing it, and do not re-litigate it before 1.1. The cheap version of the same instinct is the monthly poster (C2); the fun version is ghost chase (B2). |
