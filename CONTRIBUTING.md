# Building and testing Revert

## Requirements

- Xcode 26 or newer (the project builds against the iOS 26 SDK).
- An iPhone simulator running iOS 18.0 or newer.
- No package manager step: the one dependency (ImmersiveMap) resolves through
  Xcode's SPM support on first open.

## Build

```bash
xcodebuild build \
  -project revert.xcodeproj \
  -scheme Revert \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

## Test

```bash
xcodebuild test \
  -project revert.xcodeproj \
  -scheme RevertTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

The unit suite runs in the app host. If a manual ride left an unsaved journal in
the simulator's app container, the recovery test can see it; uninstall the app
or delete `Application Support/RevertJournal` before a clean run.

## Lint (optional)

`Scripts/lint.sh` runs SwiftFormat and SwiftLint when they are installed. The
configs live in `.swiftformat` and `.swiftlint.yml`; neither tool is required to
build.

## Conventions

- One type per file where practical; file names match the type.
- Tests are Swift Testing (`@Test`, `#expect`) in `RevertTests/`.
- Every user-visible fix gets a test unless it needs hardware (a real GPS fix,
  a helmet).
- Keep `REFINEMENTS.md` honest: tick only what is verified.
