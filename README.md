# Revert

A motorcycle ride planner and companion for iPhone. Point it at a destination
and it hunts for the twistiest route instead of the fastest one, then navigates
it with turn-by-turn guidance, lean-angle tracking and voice prompts.

Everything runs on the phone: no accounts, no analytics, no server of our own.

The product is **Revert**. The clone folder and the Xcode project file are
lowercase (`revert/`, `revert.xcodeproj`); the target, scheme, app and module
are `Revert`; the person on the bike is still a *rider*.

> **Status:** personal project, pre-1.0. Expect rough edges and breaking
> changes between commits.

## What you need

| | |
| --- | --- |
| Xcode | 26.0 or newer (developed on 27.2) — the deployment target is iOS 26.0 |
| macOS | whatever Xcode 26+ requires |
| Device / simulator | iPhone running iOS 26+, or the iOS 26 simulator runtime |
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

CarPlay navigation needs the `com.apple.developer.carplay-maps` entitlement,
which Apple grants per App ID on request. It is wired for **simulator builds
only** (`Revert+CarPlay.entitlements`), so anyone can try it with the CarPlay
simulator without an approval; a device build deliberately omits it and will
simply not appear on a car screen. See [CARPLAY.md](CARPLAY.md).

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

Offline data can be downloaded ahead of time from **Offline** in the app.

## Tests

```bash
xcodebuild test -project "revert.xcodeproj" -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`RevertUITests` drives the real UI and is slower; `RevertAuditUITests` is a
screenshot-heavy audit pass that is allowed to fail in CI.

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

