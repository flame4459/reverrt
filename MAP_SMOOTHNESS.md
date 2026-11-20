# Map smoothness — what the engine gives us, what it costs us, and the numbers that decide it

One guideline for the ImmersiveMap renderer as shipped in Revert. The design and
renderer-choice docs were retired once the feature landed; the code is
`ImmersiveMapRenderer.swift`, `MapKitRenderer.swift` and `MapExperience.swift`.
Labels keep their own guide: [DECLUTTER.md](DECLUTTER.md).

The short version: the renderer is capable, the app drives it the long way round,
and six fixes put us in the same frame budget as the apps we are comparing to.

**Applied so far (build verified, simulator):**

- R1 direct camera drive — `RideCameraDriver` notifies observers every display
  tick and publishes into SwiftUI only at 15 Hz; `RideImmersiveMapView` jumps the
  camera from the observer. The ride screen no longer re-evaluates at 60 Hz.
- R2 ProMotion — `CADisableMinimumFrameDurationOnPhone` set; render loop asks for
  120 fps with continuous rendering off.
- R4 partly — ribbon bucket 50 m → 100 m.
- R5 — trees, shadows, atmosphere and globe disabled in the navigation view.

**Also applied:** R3 (the rider is an ImmersiveMap pin moved with
`pins.move`), R4's casing/RDP path, the frame HUD (`-debugFrameHUD`), S1's
prediction lead and 120°/s heading slew, and the compact floating car HUD.
Still open: a real pre-extracted PMTiles region, S3 prewarm, S4 resolution
policy, and the upstream trim/progress shader.

---

## 1. What is already right in the package

~88k Swift LOC, real Metal, and it already anticipates our exact use.

| Already there | Why it matters |
| --- | --- |
| A paced `CAMetalDisplayLink` loop (`UI/RenderLoopPacing.swift`) | Frames are driven by the display, not by a SwiftUI redraw |
| `externalCameraDrive`, an activity documented as "an app driving the camera once per frame … a follow camera fed by a location stream" | Jump-per-frame is the *intended* API, held through a grace period so a series of jumps does not lose vsync |
| Thermal and Low Power caps (`PowerConstraintState`) | 60 fps under serious thermal pressure, 30 under critical, ProMotion revoked when the device is constrained |
| `onFrameRendered` (`UI/Runtime/ImmersiveMapRenderedFrame.swift`) | Hands back `cpuDuration` and the target presentation timestamp — a frame budget meter in the box |
| `ImmersiveMapSettings: Equatable` | Re-applying identical settings does not rebuild the map |
| `ImmersiveMapPinsController.move(id:to:)` | A marker moves as a uniform update, not a source re-upload |

## 2. What is costing us, ranked

### R1. The camera goes through SwiftUI every frame — the big one

`RideCameraDriver.tick()` sets `frame` on every display-link callback; the view
body re-evaluates at ~60 Hz and `.onChange(of: cameraFrame)` calls
`camera.jump`. Three hops where the engine expects one.

**Fix.** Drive the controller from `tick()` directly (pass it in at `start()`),
mark `frame` `@ObservationIgnored` for the camera path, and publish a separate
1 Hz readout for anything the UI displays.

**Effect.** Removes ~60 body evaluations and their layout passes per second.

### R2. ProMotion is off

`CADisableMinimumFrameDurationOnPhone` is missing from `Info.plist`, so iOS caps
the app at 60 Hz on 120 Hz hardware no matter what the engine requests.

**Fix.** Add the key (`<true/>`); set `RenderLoopSettings.interactionFramesPerSecond`
to 120 in ride mode and 60 in planning. The engine already lowers the rate under
thermal pressure.

### R3. The puck re-registers a layer on every fix

`refreshLayers()` registers a `ride-rider` point source with a new identity per
coordinate and rebuilds the whole layer array with `layers.set(...)` — a geometry
upload and a list rebuild for a marker that moved a few metres.

**Fix.** Register a pin once, then `pins.move(id:to:)` per fix. Keep the layer
array static.

### R4. The ribbon re-uploads the remaining route every 25 m

`progressBucket = Int(progress / 25)` rebuilds both polylines and re-registers
them; on a 5 000-point loop that is a full upload several times a second.

**Fix, in order.** Bucket at 100 m; simplify the drawn geometry with RDP at ~5 m;
re-register the remaining route only when the split crosses a vertex bucket; draw
casing as two layers (9 pt dark under 5 pt accent) because the polyline style has
colour and width only.

### R5. Scene features we do not need

Relief, trees, shadows, atmosphere and the globe are all on by default in a
navigation view.

**Fix.** Ride mode: `.trees(isEnabled: false)`, `.shadows(isEnabled: false)`,
`.atmosphere(isEnabled: false)`, `.globe(isEnabled: false)`, keep `.night()` and
`modelArchive(nil)`, trim label density through `LabelStyles`. Measure the delta
with `onFrameRendered.cpuDuration`.

### R6. Tiles and caches

A bundled `region.pmtiles` is preferred with the hosted archive as fallback —
already better than MapKit. Two things to verify: the memory budget for ride mode
(default 128 MB), and that the local archive actually wins on device. A silent
fallback to streaming would explain stutter in poor coverage. Pre-extract the
region so a ride never depends on the network.

## 3. The numbers that decide it

After R1–R6:

- 120 fps on ProMotion, 60 elsewhere, camera updated once per frame from the
  filtered pose.
- **`cpuDuration` p95 under 6 ms** at 60 Hz — roughly half the 8.3 ms budget at
  120 Hz left for everything else.
- **Zero missed presentations** during a pan.
- **No hang over 100 ms** anywhere in the ride flow (the existing
  `MapHangMonitor` logs those).
- A ribbon that advances for a few hundred bytes per 100 m, and a puck that moves
  as a uniform.

A 30-minute ride meeting those four numbers is the definition of "smooth enough
to compare". Anything short of it is still measurable work, not an opinion.

## 4. How to verify it

1. **Signposts** — `MapPerformance.camera`, `.overlay`, `.search` around the
   three paths; `os_signpost` around the collision solve once [DECLUTTER.md](DECLUTTER.md)
   lands.
2. **Frame HUD (add it)** — a debug overlay fed by `onFrameRendered`:
   `cpuDuration` p50/p95, missed presentations, effective Hz (60 vs 120). This is
   the number to optimise; a feeling is not.
3. **Instruments** — Time Profiler, Hangs, Core Animation.
4. **The honest test** — record the same road in Google Maps and Revert at
   240 fps, step frame by frame, list the specific tells. Camera lead, heading
   overshoot on turn-in, zoom anticipation: each is a parameter, not a rewrite.

## 5. The one upstream patch worth doing

If R1–R6 are not enough: a **trim/progress uniform on the polyline shader**, so
the ribbon advances by changing one number instead of re-uploading geometry. Two
smaller ones alongside it: casing in the polyline style (one draw instead of
two), and label density per zoom (a cheaper alternative to disabling labels).

The solver and renderer are `internal`, so this is an upstream PR, not a fork —
the changes are additive and the maintainer accepts PRs.

## 6. Where it will still be visibly ours

Tile loading on a weak connection (fix: pre-extracted region), label pops on big
zoom changes (fix: [DECLUTTER.md](DECLUTTER.md)), SwiftUI chrome animating over a
120 fps Metal view (fix: static chrome during motion, or draw it in the
renderer), style changes rebuilding the map (fix: never mid-ride), and thermal
throttling on long hot rides (the engine caps by design; Google has the same
physics, better camouflage).

Realistic grade in steady-state motion: camera and ribbon 9/10, transitions 8/10,
labels 7/10, tile loading 6/10. Google's data is not in the comparison; Google's
*feel* is, and it is reachable.

---

## 7. Even smoother — the second tier

R1–R6 remove the waste. This tier removes the *remaining* millisecond-level tells —
the ones you feel as "almost Google" rather than "janky". Each is independent.

### S1. Predict, don't follow

A camera that follows the filtered fix is always one GPS interval late. Lead the
target by ~150–250 ms of travel (`position + velocity × Δ`) and slew-limit heading
to ~120 °/s so intersections don't snap the view around. Combined with the
look-ahead offset in `RideCameraEngine`, the puck sits where the rider's eyes
already are.

Cost: a few lines in the camera engine. Effect: the single biggest "feels alive"
improvement after R1.

### S2. Frame-phase discipline

The camera pose must be read at the *start* of the frame, before any encoding, and
nothing in the frame may allocate: no formatters, no `Date`, no array growth, no
`autoreleasepool` churn. Format ETA and distance once per second into preallocated
strings; the render loop only interpolates numbers. Wrap tile decode in
`autoreleasepool` so a burst of tiles doesn't leave garbage for the next frame to
collect.

Cost: audit + small refactors. Effect: removes the occasional 20 ms spike that is
invisible in averages and obvious at 120 Hz.

### S3. Tile residency and prefetch

Two changes with outsized returns:

1. **Prewarm.** Create the map view at app launch, off-screen, so shaders compile
   and the first tiles arrive before the ride screen appears.
2. **Pre-extract the corridor.** At plan time, extract a PMTiles region around the
   route (a background job) and memory-map it. A ride then never streams — the
   difference between "smooth" and "smooth until the first dead zone".

Cost: one background job and a cache directory. Effect: eliminates the only
remaining category of multi-frame stalls.

### S4. Dynamic resolution and MSAA policy

Render at 85 % of native and upscale when the display is at 120 Hz, 100 % at 60 Hz.
Disable MSAA above 90 Hz and under thermal pressure; a slightly softer edge is
invisible at speed, a dropped frame is not.

Cost: one setting, two branches. Effect: buys roughly 15–20 % GPU headroom exactly
where the budget is tightest.

### S5. A quality ladder, not a cliff

Define the degradation order and let thermal and Low Power walk it:
trees → shadows → MSAA → resolution scale → 60 fps → 30 fps.

The engine already caps frame rate by thermal state; this extends the same idea to
visual features so the *rate* is the last thing to go. The rider notices features
disappearing far less than a stutter.

### S6. Chrome that never reflows

The maneuver card and ETA pill are SwiftUI over a Metal view. Keep them:

- fixed size, tabular digits, monospaced numerals;
- updated at 1 Hz, never per frame;
- free of blur, shadow and material while the map is moving;
- hit-testing disabled where they are purely informational.

If a card animation still drops a frame at 120 Hz, freeze the card during motion
and animate it only when stopped. The map must never wait for SwiftUI.

### S7. Input latency

Gestures must be answered in the same frame. Keep pan/zoom/tilt owned by the map
view; no SwiftUI `DragGesture` over it, no `simultaneousGesture`, no hit-test
passthrough that delays the first touch. A map that reacts one frame late feels
heavy no matter how smooth the animation is.

### S8. Instrument the tail, not the average

Track `hitch ratio` (frames over 1.5× the budget) and p99 frame time, not just p50.
A map with a p50 of 4 ms and a p99 of 40 ms feels worse than one that sits at 8 ms.
Target: hitch ratio under 0.5 %, p99 under 12 ms at 60 Hz / 9 ms at 120 Hz.

---

## 8. The last five percent — GPU and pacing

Past the second tier, the remaining gains are in the Metal pipeline and in
*consistency* rather than features. This is the point where "smoother" stops being
a product decision and becomes a engineering budget.

### T1. Never let the CPU wait on the GPU

Three drawables, one in flight per frame, a semaphore before encoding and a
`addCompletedHandler` that signals it. Any `waitUntilCompleted` on the frame path
is a stall by definition. If the trace shows the CPU idle at the end of a frame,
the GPU is the constraint and no amount of camera tuning will help.

Measure with **Metal System Trace**, not Time Profiler: it shows GPU busy time per
pass, encoder gaps and drawable waits side by side.

### T2. Pick a rate and hold it

A steady 90 fps reads smoother than a 120 fps that dips to 96. Prefer
`interactionFramesPerSecond = 90` on ProMotion phones unless the trace shows
headroom, and let thermal pressure step down rather than oscillate. Consistency is
worth more than peak rate — this is the cheapest perceived-smoothness win left.

### T3. Sensor fusion for the puck

GPS at 1 Hz with speed dead-reckoning is good; adding the accelerometer and gyro
between fixes is what makes a puck glide instead of step. CoreMotion at 25–50 Hz,
fused with the route constraint, means the camera interpolates from a motion
signal rather than a position guess.

Cost: a small fusion layer and a calibration pass. Effect: visible immediately on
slow corners, where dead-reckoning drifts and sensor fusion does not.

### T4. Fewer vertices, pre-simplified

The cheapest triangle is the one not submitted. Pre-tile the corridor geometry at
the zooms a ride actually uses (14–17) with Douglas–Peucker already applied, drop
POI and landcover layers below zoom 15, and keep building extrusions off entirely.
This is tile-pipeline work, done once, and it pays on every frame afterwards.

### T5. Amortise background work into idle frames

Tile decode, route simplification and label layout are bursty. Give them a small
per-frame budget (0.3–0.5 ms) spent only when the frame has slack, instead of
letting a new tile land as a 15 ms spike. A queue drained eight frames early is
invisible; the same work in one frame is a hitch.

### T6. Stop when the trace is clean

The rule that keeps this from becoming an infinite optimisation: **stop when a
30-minute ride shows p99 under 12 ms, hitch ratio under 0.5 %, zero drawable waits
over 1 ms and zero GPU pass over budget.** Past that point the returns are
below human perception and the work belongs upstream, not in Revert.

## 9. Order of work

| Day | Work |
| --- | --- |
| 1 | R1 direct camera drive (the pending one), R2 ProMotion |
| 2 | S1 prediction + slew limit, R3 pin move |
| 3 | R4 ribbon, S4 resolution/MSAA policy |
| 4 | S3 prewarm + corridor extraction, S5 quality ladder |
| 5 | S6 chrome, S7 input latency, S8 tail metrics |
| 6 | 240 fps comparison; decide on the trim uniform patch |
| 7 | T2 stable-rate policy, T5 idle-frame budget |
| 8 | T3 sensor fusion, T4 pre-simplified tiles |
| 9 | Metal System Trace pass; apply T6 and stop |
