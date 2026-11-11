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
