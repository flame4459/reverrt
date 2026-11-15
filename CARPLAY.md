# CarPlay

Revert is a CarPlay **navigation** app (maps category). With the phone connected to
a CarPlay vehicle, the car screen gets the live ride: the planned route on a map,
turn-by-turn cards, distance/time remaining, and a list of saved rides and places
to start from. Rides started or ended on either screen stay in sync.

## What the car screen offers

- **Live map** rendered with MapKit in the CarPlay window: the route line, the
  destination/start-finish marker, and the rider's location. Pan, pinch, rotate
  and the recenter button are wired to `CPMapTemplateDelegate`.
- **Turn-by-turn guidance** from the same `NavigationManager` the phone uses:
  maneuver symbols and instructions, next turn, distance to the maneuver,
  remaining distance and ETA. A reroute starts a fresh guidance session.
- **Rides list** (the list button in the navigation bar): saved rides from the
  shared SwiftData store, Home, Work, recent destinations, and a destination
  search using `CPSearchTemplate` (keyboard or Siri).
- **Start / replace / end** flows. Starting a ride while another is active asks
  for confirmation on the car screen. Ending a ride asks "Keep riding" vs
  "End ride".
- **Background navigation.** A live route holds a background-location lease, so
  guidance keeps working while the phone is locked or stowed. Voice prompts use
  the existing `Speaker` and the app's background audio mode.

## Project wiring

| Piece | Where |
|---|---|
| `com.apple.developer.carplay-maps` entitlement | `Revert+CarPlay.entitlements` (simulator builds only — see below) |
| CarPlay scene manifest (`CPTemplateApplicationSceneSessionRoleApplication`) | `revert/Info.plist` |
| Scene delegate | `revert/CarPlaySceneDelegate.swift` |
| Map template + guidance + list + search | `revert/CarPlayRideCoordinator.swift` |
| Map window content | `revert/CarPlayMapViewController.swift` |
| CarPlay-agnostic text, snapshots and destination data | `revert/CarPlaySupport.swift` |
| Shared navigation + data store | `revert/RevertServices.swift` |
| Unit tests | `RevertTests/CarPlayTests.swift` |

The CarPlay files are compiled only where the CarPlay framework exists
(`#if canImport(CarPlay)`), so the macOS/visionOS destinations keep building.

## Signing: why the entitlement is simulator-only

CarPlay is a gated capability. Until Apple approves it for the App ID, an
automatic-signing device build fails before it starts:

```
error: Entitlement com.apple.developer.carplay-maps not found and could not be
included in profile. This likely is not a valid entitlement and should be
removed from your entitlements file.
```

So the project ships two entitlement files and picks one by destination:

| Destination | Entitlements file | CarPlay key |
|---|---|---|
| iOS Simulator | `Revert+CarPlay.entitlements` | yes |
| iOS device / archive | `Revert.entitlements` | no |

That is a build-setting conditional in the app target, not a scheme:

```
CODE_SIGN_ENTITLEMENTS = Revert.entitlements;
"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = "Revert+CarPlay.entitlements";
```

Device builds sign cleanly and run everything except CarPlay; simulator builds
include the key, which is what the CarPlay Simulator checks. Neither needs an
approved profile today.

## The Dashboard: CarPlay without the entitlement

Apple gates the CarPlay *app*, not the CarPlay *screen*. Since iOS 26, widgets
and Live Activities surface on the CarPlay Dashboard with no CarPlay entitlement
(the dashboard ride card itself needs iOS 18, where the small activity family was
introduced; iOS 17 gets the lock-screen card only)
at all — in Apple's own words from
[WWDC25 session 216](https://developer.apple.com/videos/play/wwdc2025/216/),
"you can make them available to drivers in CarPlay, even if you don't have a
CarPlay App."

So a device build carries two independent surfaces:

| Surface | What it shows | Entitlement |
|---|---|---|
| CarPlay app (`CPMapTemplate`) | Full map, car-side lists and search | `com.apple.developer.carplay-maps` — Apple approval |
| Dashboard Live Activity | Next maneuver, distance, remaining + ETA | none |
| Dashboard widget | "Start a loop", or "Ride in progress" | none |

The Live Activity is the riding surface, because a widget is limited to a
timeline budget of a few dozen refreshes a day — fine for "last ride", useless
for a turn cue. It declares `supplementalActivityFamilies([.small])`, the family
CarPlay and the Watch Smart Stack render, and switches to a three-fact card
there (no End button: head-unit touch is unreliable, and ending a route at speed
should not be one accidental tap away). The widget is the parked surface —
`systemSmall`, deep-linking to `revert://plan`.

The rider opts in per vehicle under **Settings → General → CarPlay → [vehicle]**;
Live Activities also have a toggle in the CarPlay Settings app.

### Car mode in the Dashboard snapshot

Since the car surfaces are Dashboard surfaces, the widget and Live Activity
share a `CarWidgetSnapshot` in the app group. It carries the mode (parked /
driving / paused / arrived / simulation), vehicle type, next turn, instruction,
remaining, ETA, speed, speed limit, lap, hazard and the SIM flag. The Dashboard
widget uses it for its parked/riding/arrived/simulation cards, and the Live
Activity's small car card adds speed/limit, lap, hazard and SIM to the turn
card. Both are updated from the phone's navigation state; no coordinates are
written into the snapshot.

### Checking it

- **Simulator**: install a simulator build, then *I/O → External Displays →
  CarPlay*. Start a ride to see the Live Activity on the Dashboard, and add the
  Revert widget from the Dashboard's widget strip.
- **Phone**: the same widget renders in the Home Screen gallery, and the Live
  Activity on the Lock Screen in its wide layout (which keeps the End shortcut).

The CarPlay app code stays in place for the day Apple approves the entitlement;
nothing above depends on it, and nothing below is needed for the Dashboard.

## Before it works in a vehicle

1. Request the CarPlay Navigation entitlement at
   <https://developer.apple.com/contact/carplay>.
2. In the Apple Developer portal, enable **CarPlay Navigation** for the
   `com.davidmolina.Revert` App ID and regenerate the provisioning profile.
3. Switch device signing to the CarPlay entitlements: delete the
   `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]` override in the app target and
   set `CODE_SIGN_ENTITLEMENTS` to `Revert+CarPlay.entitlements` (or copy the
   `com.apple.developer.carplay-maps` key into `Revert.entitlements`).
4. Sign with the regenerated profile. No code changes are needed.

## Testing

- **Unit tests** cover the CarPlay text mapping, destination loading (saved
  rides, recents, Home/Work), guidance snapshots, and a check that the scene
  delegate name in `Info.plist` resolves at runtime:

  ```
  xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    CODE_SIGNING_ALLOWED=NO -only-testing:RevertTests/CarPlayTests
  ```

- **Map preview on the phone**: launch with `-debugCarPlayMap` to render the
  exact `CarPlayMapViewController` used by the car window (map content only, no
  CarPlay chrome). Handy for checking the route line and marker on a simulator
  without a vehicle.

- **CarPlay Simulator**: in Xcode's Simulator, choose *I/O → External Displays →
  CarPlay*. This requires a Simulator build that includes the CarPlay
  entitlement, and the regular simulator app on the Mac. A real head unit is the
  only place to verify templates, focus/knob input, vehicle display limits, and
  phone-locked behavior.

## Notes and limits

- CarPlay renders the templates; the app does not draw a custom HUD, hazard
  banners, or speed-limit badges on the car display. Those stay on the phone.
- Destination search for Home/Work/recents uses `MKDirections`; saved scenic
  loops already carry their full route and road graph, including rerouting data.
- The car screen is deliberately map-only. Every overlay and control is a
  CarPlay template, as the platform requires.
