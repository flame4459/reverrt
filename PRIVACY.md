# Privacy

Revert is a local-first app. There is no account, no analytics SDK, no
advertising identifier and no server of our own.

## What stays on the phone

- Recorded rides, track points, lean and speed data.
- Saved routes, trip days, places, the garage and service notes.
- Downloaded road data, hazard caches and elevation profiles.
- Diagnostics: coarse events and error text only. No coordinates, no place
  names, no ride tracks. Exportable from About → Share diagnostics.

## What leaves the phone, and why

| Destination | Data | When |
| --- | --- | --- |
| OpenStreetMap Overpass mirrors | Bounding box of the area being planned | Planning a loop or directions |
| Apple Maps (`MKDirections`) | Start and destination coordinates | Point-to-point directions and reroutes |
| Open-Meteo / MET Norway | Approximate coordinates | The weather strip and conditions card |
| GitHub (`flame4459/reverrt`) | Nothing | Only if you open a link from About |

Requests carry no account, device name or ride history. Coordinates are rounded
to the area needed for the answer; the app does not upload a track.

## Permissions

- **Location**: planning, recording, navigation. "Always" is only requested so a
  ride keeps recording with the screen off.
- **Motion & Fitness**: lean angle and g-force. Denying it leaves those gauges at
  zero; nothing else changes.
- **Microphone and Speech Recognition**: hands-free commands and the companion.
  On-device recognition is requested; the system may fall back to Apple's speech
  service for some languages. Both are optional.
- **Bluetooth**: helmet audio and the handlebar remote.
- **Notifications**: service due and the monthly recap. Off by default until you
  save a route.
- **Files**: importing or exporting GPX, and sending a track to a car app.

## Deleting data

About → Clear diagnostics removes the diagnostics file. Deleting a ride removes
its points. Uninstalling the app removes everything in its sandbox, including
downloaded regions and journals.

## Children

The app is not directed at children and collects nothing.

## Contact

Open an issue at <https://github.com/flame4459/reverrt/issues>.
