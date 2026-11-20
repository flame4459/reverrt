# Declutter engine — design

The premise changed once I read the code: **ImmersiveMap already ships a label
collision solver.** Rebuilding it would be throwing away a good one. What it
does not have is any idea that it is on a motorcycle with a route, a maneuver
card and a speed sign. This designs that layer.

Source: `Sources/ImmersiveMap/Labels/Collisions/` — `LabelCollisionSolver`,
`BaseLabelRank`, `CollisionScratchBuffer`, plus road-label placement in
`Labels/Road/`.

**Status:** partially implemented through the public ImmersiveMap surface:
POI plates are suppressed in ride mode, collision spacing is widened, landmark
density and local detail are reduced. The full seeded-occlusion, route-aware
ranking and turn-focus solver needs the internal package patch described below.

---

## 1. What exists

- **One-pass greedy solve, strict order.** Every candidate — base labels and
  road instances together — is ranked (collision priority, secondary priority,
  sort priority, tile order, stable key) and accepted if none of its glyph boxes
  overlaps an already-placed box.
- **Glyph boxes, not label boxes**, so a rotated road label blocks only where its
  letters actually are.
- **A 64 px grid with intrusive lists** over flat buffers: nothing allocates
  after the buffers reach the frame's size.
- **No budget, no seeding, no eviction.** The decision for a pose is a pure
  function of the pose; fades smooth the changes between frames.
- **Priorities are fixed at tile parse** (`LabelPlacementMeta`), not per frame.

That last point is the crux: the solver is deterministic and cheap, but it cannot
know that the road ahead matters more than the road behind, or that a rectangle
of the screen is covered by the maneuver card.

## 2. What Revert needs

Four additions, all fed in per frame:

| # | Capability | Why |
| --- | --- | --- |
| S1 | **Seeded occlusion rects** | Labels must never appear under the maneuver card, ETA pill, control rail, speed sign or status bar |
| S2 | **Route-aware ranking** | The next turn's road name and roads on the route outrank everything else; off-route labels demote |
| S3 | **Density by speed** | At 70 mph the screen carries four labels, not twenty; the cap is speed- and zoom-driven |
| S4 | **Turn focus** | Inside ~200 m of a maneuver, the turning road wins and everything else fades |

Optional, if flicker shows up in the 240 fps review:

| S5 | **Stickiness** | A label visible last frame gets a capped rank bonus, so panning does not shuffle it |

## 3. Design

### 3.1 Context injected per frame

```swift
struct LabelContext: Sendable {
    var routeRoadKeys: Set<String>        // refs/names on the planned route
    var nextTurnRoadKey: String?          // the maneuver's road
    var metersToTurn: Double
    var speedMetersPerSecond: Double
    var occlusion: [SIMD4<Float>]         // screen rects, points: minX,minY,maxX,maxY
    var maxPlacements: Int                // density cap
    var minimumRank: Int                  // labels above this rank are skipped
    var zoom: Double
}
```

Fed from the app through a controller, not through the view body — the same
discipline as the camera (see [MAP_SMOOTHNESS.md](MAP_SMOOTHNESS.md)).

### 3.2 S1 — seeded rects

Before the first candidate, insert each occlusion rect into the grid as a placed
box with no owner. Cost: a few dozen cells per rect, once per frame. Effect:
chrome is treated like a label that always wins.

Implementation: `solve(...)` gains `seedBoxes: [SIMD4<Float>]`, inserted after
the grid is cleared and before the merge. No changes to the solver's ordering.

### 3.3 S2 — route-aware ranking

Do not re-rank the base labels (their rank is baked per tile). Instead bias at
merge time, where the app's context is available:

```
effectiveRank = baseRank
              - (isNextTurn ? 3_000 : isOnRoute ? 1_500 : 0)   // lower wins
              + (isOffRoute && navigating ? 500 : 0)
```

Boosts are capped below the pin and safety strata, so a label can never outrank
the rider puck, a hazard, or the speed sign. Ties fall back to the existing
stable key, so the result stays deterministic.

### 3.4 S3 — density by speed and zoom

Two knobs, both from the context:

- `minimumRank`: raised with speed, so minor roads disappear before arterials.
- `maxPlacements`: `clamp(24 - speed_mps / 2, 6, 24)`, floor 4 while a maneuver
  is within 200 m (the turn's label must survive).

The solve already stops when candidates run out; a cap just stops earlier. Same
determinism, less CPU, calmer screen.

### 3.5 S4 — turn focus

Inside 200 m of a maneuver:

1. Boost the turning road's label by 3 000 (it sits above route labels).
2. Demote everything not on the route by 500.
3. Add a 120 × 80 pt rect over the lane strip's position to `occlusion`, so no
   label competes with the arrows.

### 3.6 S5 — stickiness (only if needed)

A small `UInt8` per label: frames since last placed. Bonus = `min(age, 20) × 40`
rank points, reset when zoom changes by more than 0.5 or the route changes. Caps
at 800 — enough to stop shuffle, not enough to keep a stale label through a turn.

This is the one change that makes the solve a function of history, so if it ships,
the tests must run fixed frame sequences rather than single poses.

## 4. Performance budget

- Candidates in a nav view: ~250 labels, ~2 500 glyph boxes. The existing solver
  handles that in well under 1 ms on an iPhone 13-class device.
- Budget: **0.8 ms p95** for the solve, measured by signpost around `solve`.
- Allocations: none after warm-up; keep the new seed list in the same scratch
  buffer pattern (`CollisionScratchBuffer`).
- If the cap is hit, stop; never grow the grid per frame.

## 5. Tests

1. **No overlaps** — property test with random boxes: every accepted label's boxes
   are disjoint from every earlier accepted box and every seed.
2. **Chrome wins** — a label centred under a seed rect is rejected.
3. **Route beats class** — an on-route minor road beats an off-route arterial with
   a better base rank.
4. **Turn focus** — inside 200 m, the turning road is placed even at a high speed
   cap.
5. **Flicker** — sweep the camera by 0.5 px/frame over 300 frames; count labels
   that toggle more than once. Target: under 2 % of labels.
6. **Determinism** — same pose, same context ⇒ identical visible set.

## 6. Rollout

The solver is `internal` to the package, so this is a fork or an upstream PR. The
maintainer accepts PRs and the change is additive (`seedBoxes` plus a context
struct), so a PR is the clean path — and it keeps us off a permanent fork of a
renderer we do not control. If the PR stalls, patch locally and keep the diff
small: one file, plus the context plumbing.

## 7. What this buys

The screen stops fighting itself. Labels never sit under the card, the road you
are about to turn onto is always named, minor roads vanish as speed rises, and
nothing shuffles while you pan. That is most of what "Google's labels feel
calm" actually means — not a better font, a stricter set of rules about who wins.
