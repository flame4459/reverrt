# Privacy

Revert is a local-first app. There is no account, no analytics SDK, no
advertising identifier and no server of our own.

## What stays on the phone

- Recorded rides, track points, lean and speed data.
- Saved routes, trip days, places, the garage and service notes.
- Downloaded road data, hazard caches, elevation profiles and offline map
  regions (PMTiles files in `Application Support/MapRegions`).
- Diagnostics: coarse events and error text only. No coordinates, no place
  names, no ride tracks. Exportable from About → Share diagnostics.
- Ride debug transcripts: written only while a ride is recorded, in
  `Application Support/RideDebug`, and they *do* contain the rider's coordinates,
  the route and a position sample every few seconds. They never leave the phone
  unless you tap Share on one. Turning recording off in Settings stops them.
- Backups and car-handoff GPX files: written to the app's Documents folder, which
  is visible in the Files app, so they survive a delete and redownload.
  A backup contains your whole history, so treat the exported file as private.

## What leaves the phone, and why

| Destination | Data | When |
| --- | --- | --- |
| OpenStreetMap Overpass mirrors | Bounding box of the area being planned | Planning a loop or directions |
| Apple Maps (`MKDirections`) | Start and destination coordinates | Point-to-point directions and reroutes |
| Open-Meteo / MET Norway | Approximate coordinates | The weather strip and conditions card |
| Open-Meteo (elevation) | Route sample coordinates, 4 decimal places (~11 m) | Elevation profile when a route is planned |
| `tiles.immersivemap.dev` | The map area you are looking at (PMTiles range requests) | When the ImmersiveMap renderer streams a map instead of using a downloaded region |
| Your region host (configured in `MapRegions.json`) | The region file request only | When you download an offline map region |
| GitHub (`flame4459/reverrt`) | Nothing | Only if you open a link from About |

Requests carry no account, device name or ride history. Weather coordinates are
rounded to the area needed for the answer. The elevation profile sends the
route's own sample points (four decimals, about 11 m) because that is what an
elevation query needs; it is the one place a route leaves the phone, and only when you open the
profile. The map renderer's tile archive is hosted, not bundled, so map views
require a connection. The app does not upload a recorded track.

## Permissions

- **Location**: planning, recording, navigation. "Always" is only requested so a
  ride keeps recording with the screen off.
- **Motion & Fitness**: lean angle and g-force. Denying it leaves those gauges at
  zero; nothing else changes.
- **Microphone and Speech Recognition**: hands-free commands and the companion.
  On-device recognition is requested; the system may fall back to Apple's speech
  service for some languages. Both are optional. The **"Hey Ace"** wake word is
  on by default while a ride is recording and keeps the microphone open, which
  costs battery; switch it off in Settings → Companion to use the mic button
  instead. No audio is written to disk.
- **Bluetooth**: helmet audio and a Bluetooth microphone.
- **Notifications**: an optional backup reminder. Revert never asks at launch;
  it asks only when you turn on **Remind me every 6 days** in Settings → Data &
  privacy → Backup & restore.
- **Files**: importing or exporting GPX, and sending a track to a car app.

## Deleting data

About → Clear diagnostics removes the diagnostics file. Deleting a ride removes
its points. Uninstalling the app removes everything in its sandbox, including
downloaded regions and journals.

## Children

The app is not directed at children and collects nothing.

## Contact

Open an issue at <https://github.com/flame4459/reverrt/issues>.
