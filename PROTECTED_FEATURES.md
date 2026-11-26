# Protected features: Loop and Sprint generators

The route generators are core features, not part of the map renderer. A change
to how maps are drawn must not change what these produce.

## The contract

```
UI (PlanView, SprintPlannerView)
        │
        ▼
RoutePlanner  ──────────────►  MapKit (MKDirections)      online candidates / fallback
        │                      TwistyLoopEngine            online loop candidates
        ▼
RouteBuilder (pure graph)  ──►  PlannedRoute  ──►  saved routes, GPX, replay, renderer
        ▲
        │
RoadStore / GraphCache / RoadGraph        road data (cached = offline)
```

- **The generators' output is `PlannedRoute`**: points, cumulative distances,
  steps, kind, surfaces, laps. Every consumer (renderer, GPX, saved routes,
  replay, rivals) reads it. The renderer must consume it, never regenerate it.
- **No generator references a renderer.** `RouteBuilder.swift`,
  `RoutePlanner.swift` and `SprintPlannerView.swift` contain no reference to
  `RideMapKitView`, `RevertMapView`, `RideImmersiveMapView`, `MapRendererKind`
  or PMTiles.
- **MapKit is not only a renderer.** `RoutePlanner` uses `MKDirections` for
  A→B candidates, alternatives and fallbacks, and `TwistyLoopEngine` builds
  loop candidates with MapKit. Long loops (> 80 km) can fall back to MapKit
  entirely. Removing MapKit would break route *generation*, so it stays.

## Where they live

| Concern | Code |
| --- | --- |
| Loop algorithm (offline) | `RouteBuilder.loops` / `loopsResult` in `RouteBuilder.swift` |
| Sprint algorithm (offline) | `RouteBuilder.direct` (A* one-way) in `RouteBuilder.swift` |
| Orchestration, MapKit fallback | `RoutePlanner.requestDirections`, `RoutePlanner.planLoops` |
| Online loop candidates | `TwistyLoopEngine` |
| Road data | `RoadStore` (Overpass, cached to disk), `GraphCache`, `RoadGraph` |
| Output | `PlannedRoute` in `RouteModels.swift` |
| GPX | `GPX.export` / `GPX.parseTrack` |
| Sprint UI | `SprintPlannerView.swift` |
| Loop UI | `PlanView.swift` |

## Offline capability (verified by inspection and tests)

| Path | Needs network? |
| --- | --- |
| Loop from cached road data | No — `RouteBuilder.loopsResult` over `RoadStore` cache |
| Loop in an uncached area | Yes — the roads must be downloaded first (`RoadStore.downloadArea`) |
| Long loop > 80 km | May require MapKit (online) |
| Sprint / sporty A→B | Graph first, offline with cached roads; MapKit fallback if the graph fails |
| Map display | Depends on the archive: downloaded region > bundled starter > hosted stream |

PMTiles supply map imagery only. They are not a routing source and the
generators never read them.

## Regression tests

`RevertTests/GeneratorProtectionTests.swift` (headless, synthetic roads, no map,
no network, no SwiftData):

- loops are closed, usable, and near the requested distance at 1.5 / 3 / 6 km;
- loop generation is deterministic for identical inputs and dates;
- a loop from a different start stays closed;
- insufficient coverage fails cleanly, without crashing;
- sprint routes are connected, bounded, have steps, and snap to the requested
  endpoints across all three styles;
- an unreachable sprint destination returns nil instead of a broken route;
- a generated loop survives GPX export → import with the same distance;
- the renderer consumes a generated route without changing it, and the overview
  camera is centred on the route's bounds.

Run just these:

```bash
xcodebuild test -project revert.xcodeproj -scheme Revert \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:RevertTests/GeneratorProtectionTests
```

Existing coverage that must keep passing: `LoopFallbackTests`,
`RouteAlgorithmTests`, `LoopLapTests`, `PointToPointTests`, `GuidanceRideTests`,
`ImportFuzzTests`.

## Rules for future map work

1. Do not delete or bypass `RouteBuilder`'s graph algorithms, `TwistyLoopEngine`
   or `RoutePlanner`'s MapKit paths to simplify the map layer.
2. Do not make a generator depend on a view, a renderer, or PMTiles.
3. Any change to `PlannedRoute`'s meaning (distance, steps, closure) needs the
   generator tests updated first.
4. If a generator cannot be preserved, stop removing its dependency and report
   the blocker — do not ship a simpler approximation.
