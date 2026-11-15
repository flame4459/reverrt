# Revert

A motorcycle ride planner and companion for iPhone. Point it at a destination
and it hunts for the twistiest route instead of the fastest one, then navigates
it with turn-by-turn guidance, lean-angle tracking and voice prompts.

Everything runs on the phone: no accounts, no analytics, no server of our own.

The product is **Revert**. The clone folder and the Xcode project file are
lowercase (`revert/`, `revert.xcodeproj`); the target, scheme, app and module
are `Revert`; the person on the bike is still a *rider*.

> **Status:** personal project, pre-1.0. Expect rough edges and breaking
> changes between commits. What changed recently is in
> [CHANGELOG.md](CHANGELOG.md).

## What you need

| | |
| --- | --- |
| Xcode | 26.0 or newer (developed on 27.2) — the deployment target is iOS 17.4 |
| macOS | whatever Xcode 26+ requires |
| Device / simulator | iPhone running iOS 17.4+, or an iOS 17.4+ simulator runtime |
| Dependencies | none — no SPM packages, no CocoaPods, no generated code to fetch |

There are no API keys or `.env` files to fill in. Clone, open, run.

## Run it in the simulator

```bash
git clone <your-fork-url> revert
cd revert
open "revert.xcodeproj"
```

In Xcode pick the **Revert** scheme, choose an iPhone simulator, and
press Run. Building from the command line works too:

```bash
xcodebuild build \
  -project "revert.xcodeproj" \
  -scheme "Revert" \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

The app asks for location, motion and (for hands-free controls) microphone and
speech-recognition permission on first launch. Simulators have no GPS — set a
location with **Features ▸ Location** or
`xcrun simctl location booted set 37.7749,-122.4194`.

## Run it on a device

A device build needs your own Apple Developer account. Three things in this
repository are tied to the original author's identifiers and must be changed to
yours before Xcode's automatic signing will succeed:

1. **Signing team** — no team is set. Select the *Revert*,
   *RevertWidgets*, *RevertTests* and *RevertUITests* targets, then
   *Signing & Capabilities ▸ Team* and pick yours (repeat for each target).
2. **Bundle identifiers** — currently `com.davidmolina.Revert`,
   `com.davidmolina.Revert.RevertWidgets`, `com.davidmolina.RevertTests` and
   `com.davidmolina.RevertUITests`. These are registered to the author's
   account, so use your own reverse-DNS prefix.
3. **App Group** — `group.com.davidmolina.Revert` is shared between the app and
   the widget. If you change it, change it in all five places or the widget
   stops seeing live ride state:
   - `Revert.entitlements`
   - `Revert+CarPlay.entitlements`
   - `RevertWidgets/RevertWidgets.entitlements`
   - `revert/WidgetBridge.swift`
   - `RevertWidgets/RevertQuickWidget.swift`

The *RevertTests* target runs on the simulator and needs no signing.

### CarPlay

The full CarPlay *app* (car-side map, lists, search) needs the
`com.apple.developer.carplay-maps` entitlement, which Apple grants per App ID on
request. It is wired for **simulator builds only**
(`Revert+CarPlay.entitlements`), so anyone can try it with the CarPlay simulator
without an approval; a device build deliberately omits it and will not appear as
a CarPlay app.

**Revert reaches the car anyway.** Since iOS 26, widgets and Live Activities show
up on the CarPlay Dashboard with no CarPlay entitlement — so a device build ships
a live ride card (next maneuver, distance, ETA) and a "Start a loop" launcher.
That is the surface riders actually get today. The dashboard ride card needs the
small activity family, which is iOS 18+; on iOS 17 the Live Activity is the
lock-screen / Dynamic Island card. See [CARPLAY.md](CARPLAY.md).

## Network services

All map rendering is Apple MapKit. The additional data comes from public
endpoints, called directly from the phone:

| Purpose | Endpoint |
| --- | --- |
| Road geometry, hazards, fuel (OpenStreetMap data via Overpass) | `overpass-api.de`, `overpass.kumi.systems`, `overpass.private.coffee` |
| Elevation profile | `api.open-meteo.com` |
| Voice-pack audio | `voice-prompts-ipv6.waze.com` (plus direct MP3 import) |

**These are donated servers, not ours.** The app sends a descriptive
`User-Agent` and caches aggressively, and the Overpass mirrors are tried in
order of recent health. If you fork this and ship it to real users, expect
rate limiting, and consider running your own Overpass instance — see the
[Overpass API usage policy](https://operations.osmfoundation.org/policies/api/).
Please do not raise the request rate.

Planned graphs are cached on disk and keyed by a deterministic hash of the road
set, so re-planning in a warm area skips rebuilding nodes, edges and curvature.
A start point that is not already a node snaps to the nearest one (chunk
boundaries are every ~220 m) instead of invalidating the cache; a cold cache or
a start far from any node still builds exactly as before. Diagnostics log
`graph.cache hit|miss` with node and edge counts.

When Apple has no driving route to give — no signal, or a destination MapKit
refuses — directions fall back to the on-device graph. `RouteBuilder.direct`
runs A\* over the same cost model the loops use, and `RoadStore.corridor`
fetches only the tube of roads around the line rather than a planning disc.
Long trips are split into overlapping corridor slices, so a 200 km run is a
handful of small requests rather than one impossible one, and slices that are
already cached are not fetched again. The fallback is logged as
`directions: local fallback ok|failed` with its milliseconds, so you can tell
it apart from a MapKit route.

Offline data can be downloaded ahead of time from **Offline** in the app, or a
whole trip region can be prepared in one go: radii above 20 km are split into
overlapping 20 km cells and filled one at a time, so a weekend area is a
deliberate download instead of fifty incidental ones. Roads
and hazards are fetched as **whole areas, concurrently** — one Overpass request
each, not one per 5.5 km tile — and both are timed in diagnostics as
`offline.roads`, `offline.hazards` and `offline.done`, so a slow download can be
attributed to the network rather than guessed at. Route planning logs the same
way: `plan.roads` (fetch) and `plan.search` (graph search), which is how you
tell a slow download from a slow search.

Road geometry is kept as **overlapping saved areas**, not one file per request.
Planning 20 km from a new start point reuses every saved area that overlaps the
request and only fetches what is actually missing, so repeated riding in one
region gets cheaper instead of re-downloading the same disc from a slightly
different centre. Areas also accumulate across the distance slider: asking for
a longer loop only fetches the new ring. Diagnostics record each cache hit or
miss with its coverage percentage.

## Tests

```bash
xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`RevertUITests` drives the real UI and is slower; `RevertAuditUITests` is a
screenshot-heavy audit pass that is allowed to fail in CI.

## Units

**Settings → Ride & units → Units** offers **Automatic**, **Metric** and
**Imperial**. Automatic follows the iPhone region: US and UK use miles, mph and
feet; most other regions use kilometres, km/h and metres. The choice is saved on
the phone and applies to every distance, speed, elevation, voice prompt and
widget. The planner’s map dock has a quick metric/imperial toggle, and the
cockpit menu can switch all three modes mid-ride without leaving the map.

An existing metric/imperial choice from earlier builds is migrated once, so a
rider who previously turned metric on or off keeps that choice instead of
silently moving to automatic. Clear the automatic option to go back to the
region default.

## Ride Lab

The **Ride Lab** card on the Home screen opens the first integrated pass of the
sixteen-outline features:

- **Planning:** sun/light conditions and finish-in-the-dark warnings; the range
  ring (90% comfortable range); multi-day trips with one card per day; a saved
  loop deck; GPX import plus an optional MapKit re-plan; serverless route links;
  and an offline preflight that packs roads/hazards around the start.
- **In the ride:** “mark hazard” and “avoid this road” voice marks (plus the
  same actions in the ride menu); a ghost chase against your fastest previous
  run on the same route; and long-ride battery mode that dims the cockpit after
  ten seconds at speed. Focus mode hides the map dock but leaves a visible exit.
- **After the ride:** ride the exact track again from History, a corner report
  with entry/apex/exit speed and lean, a monthly recap poster that can be
  rendered to a PNG, setup/tyre notes per bike, and local segment detection.
- **Platform:** a “Start my usual loop” Siri shortcut picks the saved loop with
  the most completed rides. The existing Dashboard widget and Live Activity are
  unchanged.

The Lab is reachable from the Home screen’s **Ride Lab** quick action; the
planner shows the sunset/range strip under the map, the range ring (on a
motorcycle) and a **Deck** button above the route cards, and History/ride detail
expose the after-ride reports directly.

First-pass limits, deliberately visible in the UI: WeatherKit needs an Apple
Developer entitlement, so Conditions uses on-device sun times only; trips store
the day’s saved route rather than auto-generating a tour; segments are
local-only; rider marks are stored/displayed but not yet fed into the traffic
alert engine; and Focus is a cockpit-chrome mode rather than an iOS Focus
filter.

## Debugging a ride

Every recorded ride writes a plain-text transcript, on by default, listed under
**Settings → Ride debug**. One file per ride contains the settings it ran under
(with the effective default marked when you never changed it), every alert with
both the rider and the device position, every device the engine withheld and
why (`disabled`, `under-speed-gate`, `already-announced`, `cooldown`), and a
position sample every 5 seconds. That is enough to answer "why did it say
nothing at that junction" without reproducing the ride.

The transcript also carries the complete route step table, the current
step/turn/lap in every sample, `NAV-JOIN/STEP/CUE/STRAIGHT/OFFROUTE/LAP/ARRIVE`
events, settings changes, `WIDGET-STATE` for every Dashboard snapshot (including
the turn, step id, instruction, remaining/ETA, limit, hazard, reload request and
whether it was forced by a turn), `WIDGET-REFRESH` for actual WidgetKit timeline
refreshes, and `LIVE-START/UPDATE/END` for the Live Activity. CarPlay widget
reloads are forced on maneuver changes, while remaining throttled otherwise.

**Settings → Ride debug → CarPlay diagnostics** shows the current Dashboard
snapshot and the retained widget-provider log. The file also ends with a
diagnostics count summary for quick grepping.

The files stay in `Application Support/RideDebug` on the phone; the debug screen
can share one, delete one, or turn recording off. This is the only place Revert
writes coordinates to disk. The newest 40 are kept.

## Layout

```
revert/                     app sources (file-system synchronized group)
revert.xcodeproj            shared schemes live in xcshareddata
RevertWidgets/              widget extension
RevertTests/, RevertUITests/ unit and UI tests
Scripts/                   Python tooling that generates the bike sprite sheets
Assets3D/, catalog/        source assets and catalogues for that tooling
CARPLAY.md, VOICE_PACKS.md design notes for those subsystems
```

The `bikes/`, `refs/`, `pilot/`, `Meshes3D/` and `Turntables/` directories are
local working material for the sprite pipeline and are git-ignored — the app
only consumes the generated `revert/BikeSprites.xcassets`. Bikes
without artwork fall back to an SF Symbol, so the app is fully usable without
regenerating anything.

## Race formats: laps and sprints

A circuit is **three laps by default**. The loop planner has a Laps control
(1–30); the count belongs to the route, so it survives saving, replaying and
sharing. Boards are separated by lap count: a three-lap time never competes
with a five-lap time. The cockpit shows `LAP 1/3`, banks each lap with a split
and a voice call, and only finishes on the last lap.

**Sprints** are one-way timed runs. Open **Routes → Run a sprint**, pick a start
road/place and a finish road/place, choose the flavour, and build. The clock
starts at the start line and stops at the finish; there are no laps. Sprints
save, replay and share like circuits, but get their own board.

Both formats use the same start-line rule: the 3 · 2 · 1 runs when you reach
the start, not when you leave the house.

## Loops that come back

A loop you keep is a loop you can ride again. Saved loops sit on the **Routes**
screen: tap one to start it, or tap the trophy for its local leaderboard.

There is no leaderboard server. A result travels as a `revert://rival?d=…` link
carrying the rider name, the loop label, a **hashed** route key and the ride
numbers. By default it also carries a compact GPS replay, so the friend can
watch the ride on a map. Toggle **Include the ride replay** off for a time-only
link; those carry no coordinates. Either way nothing is uploaded, there is no
account, and links need Revert installed.

Two more things happen around a loop start:

* **3 · 2 · 1 at the start** — the countdown waits until you actually reach the
  first point of a loop or sprint, then starts the timer at GO. The guided ride to
  the start is not part of the time, and you can pocket the phone while it
  happens. It can be turned off in Settings → Ride recording.
* **Directions to the start** — before you cross the first route point, Revert
  asks MapKit for driving directions and shows those maneuvers in the same
  banner, with the approach drawn as a dashed amber line. The loop's own
  turn-by-turn takes over the moment you reach it.

## Directions and voice

Street names are READ aloud and shown in the banner as words, not compact
forms: **South 5th St** becomes **South Fifth Street**, and **125th Ave**
becomes **One Hundred Twenty-Fifth Avenue**. Directionals (`S` → South) and
common suffixes (`St`, `Ave`, `Blvd`, `Rd`, …) are expanded for both the
cockpit banner and the voice, so the system voice no longer rounds “5th” into
“fice”.

Guidance is more Google-Maps-like:

- a **“Continue on <road> for <distance>”** callout at the start of long
  segments, once per segment
- a 40-second mid-range turn warning, the existing 18-second warning and the
  near-turn callout, instead of only the last few hundred metres
- recorded/manoeuvre handling for slight, sharp, merge, fork, ramp, exit,
  roundabout and U-turn phrasing
- route-start, lap and arrival announcements

Navigation voice prompts are logged as `NAV-VOICE` in the ride debug transcript,
so a simulated ride can be used to verify exactly which callouts fired.

## Saved routes

Saved loops and routes can be renamed from the loop generator's saved-route
menu (or the Routes tab's saved-loop context menu). Renaming updates the saved
route and the rides already linked to it; route times, fingerprints and
leaderboards stay attached.

## Debug folder

**Settings → Ride debug** now also lists crash reports and loop-generation
failures. They live in `Application Support/RideDebug/Reports/`, beside the
ride transcripts. Crash handlers are installed at launch: an Objective-C
exception writes a full reason and stack, while a signal writes a pending report
that is promoted on the next launch. A loop that cannot be built writes the
exact request, the roads the planner had, the nearest-road distance, the graph
failure, the MapKit candidate count and the diagnostics tail — so "no loop
here" comes with a why.

**Compile every log by date** writes one text file per calendar day, combining
ride transcripts and reports, with a share button for each day. The compiled
files live in the same debug folder.

## Route simulator

Debug builds can drive the app along the active route without leaving home.
Open the cockpit's ride menu → **Route simulator**, or go to
**Settings → Ride debug → Route simulator**. It feeds synthetic fixes through
the same `LocationHub` as real GPS, so the map, turn banner, alerts, lap timer,
recorder and debug files all behave as if you were riding. Choose **1×, 2×,
3×, 4×, 5× or 10×**, pause/resume/stop at any time, and watch a live cockpit
HUD with speed, lap and progress. It works for routes, loops and sprints.

Every simulated transcript is marked `Mode: SIMULATION` and shows a **SIM**
badge in Ride debug. Stopping or finishing a simulation also writes a
**Simulation** report with the route, multiplier, distance, laps and timings,
so simulation data lands in the debug folder automatically and is included in
the per-day compiled exports. Simulated rides are **not** added to History; the
SIMULATION transcript and Simulation report are the output.

## Car mode

Start navigation and Start sprint now ask **“Car or bike today?”** for every
route, loop and sprint. The prompt notes the garage default, but the choice is
per navigation: it changes the cockpit, recording label, leaderboard vehicle,
live/widget snapshot and the active MapKit car preferences without changing
which vehicle is primary. Cancel leaves the route unstarted.

Add a **car** in the Garage (Vehicle type → Car) and make it primary. The
cockpit then switches to car mode automatically: the lean gauge, lean
calibration, helmet audio and handlebar remote disappear; the panel shows a
CAR MODE header, drive elapsed, speed/limit, g-force and drive stats. The
planner defaults cars to paved, relaxed loops (no ADV surface, no max-twisty
profile) while still allowing loops, routes and sprints. Car preferences —
electric vehicle, avoid tolls, avoid highways — are applied to live MapKit
directions while the car is primary, and the car cockpit has a dedicated
landscape strip with speed/limit, drive stats and pause/stop.

Rides store the vehicle type. Summaries, history and story posters use a car
layout instead of lean metrics, and the odometer/service log works for cars
too. Leaderboards remain shared: every result is labelled **Motorcycle** or
**Car** and the board has an **All / Bikes / Cars** filter; links carry the
vehicle type so imported times are labelled correctly.

The CarPlay Dashboard surfaces are the car display layer: the
`RevertQuickWidget` Dashboard widget now reads a shared drive snapshot
(parked / driving / paused / arrived / simulation, turn, speed, limit, lap,
hazard, ETA) and the Live Activity's small CarPlay card adds speed/limit, lap,
hazard and a SIM badge. The full CarPlay map app remains entitlement-gated;
the Dashboard surfaces do not require it.

## Story posters

Story posters now have **12 colour themes** — from OLED cockpit and Sunset pass
to Neon grid, Desert run, Alpine pass, Coast road, Monochrome, Carbon,
Vaporwave and Forest pass — and **three layouts**: Classic, Minimal and
Dashboard. Both galleries use the chosen look for the live preview and the
1080 × 1350 export.

## Bugs and ideas

Found a bug, a wrong turn or something that made you swear inside your helmet?
**Open an issue — that's the only support channel:**

<https://github.com/flame4459/reverrt/issues/new/choose>

Pick **Bug report** and fill in the form. What makes a report fixable:

| Include | Where |
| --- | --- |
| What you did, what happened, what you expected | the form |
| App version | About → This build → Version |
| iPhone and iOS version | Settings → General → About |
| Screenshots | drag them into the issue |
| Diagnostics file | About → Share diagnostics (no coordinates, no place names) |

Please **don't post your exact address or live location** — a general area is
enough. Route-planner complaints are much easier to reproduce if you say the
start area, the distance and the loop shape you chose.

Feature ideas go through the same page ("Idea or feature request"). This is a
solo, non-profit project, so a good idea and a shipped feature are different
things — but they do get read.

## Community

**Revert is free, non-profit and community-based.** It is not sold, has no ads,
no subscriptions, no accounts and no analytics. It is a personal project shared
in the open so other riders can use it, fork it or send fixes back.

Made by **whoopteh**.

## Credits and licensing

* 3D motorcycle models by Poly by Google and MiniPoly via
  [poly.pizza](https://poly.pizza) (CC-BY 3.0), and AliceCassie (CC0). They are
  used to render sprites offline and are not shipped in the binary.
* Map data © OpenStreetMap contributors, [ODbL](https://www.openstreetmap.org/copyright).
* Elevation data from [Open-Meteo](https://open-meteo.com/) (CC-BY 4.0).
* Motorcycle names and model years are used descriptively; the app is not
  affiliated with any manufacturer.

The source is released under the [PolyForm Noncommercial License 1.0.0](LICENSE):
free to use, change and share for any noncommercial purpose, including personal
and hobby use. Commercial use is not granted. See `LICENSE` for the exact terms.

The Waze voice-pack audio under `revert/BuiltInVoicePacks/` is third-party
copyrighted material and is deliberately **not** committed to this repository;
the app degrades gracefully without it (see [VOICE_PACKS.md](VOICE_PACKS.md)).

## Notes from Flame4459

This is a clone/derivative project: what you do with it, and what you choose to
post on social media from it, is your own call and not the author's. Ride
responsibly and follow the law.

**It does not work on Android at the moment** — it is a native iOS app.

### Quick install on a device

1. Open the project in **Xcode** on a Mac.
2. Connect your iPhone with a cable.
3. Pick your team and build to the device — see [Run it on a device](#run-it-on-a-device)
   for signing, bundle IDs and the App Group.

— Flame4459
