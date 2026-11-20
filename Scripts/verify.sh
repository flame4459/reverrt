#!/usr/bin/env bash
# One command for the checks that must pass before a change is "done":
# docs links, file-length budget, build, tests and (when installed) lint.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Docs links =="
./Scripts/check-links.sh

LIMIT="${FILE_LINE_LIMIT:-3000}"
echo "== File length budget (${LIMIT} lines) =="
OFFENDERS=$(find revert RevertWidgets RevertTests -name '*.swift' -exec wc -l {} + \
  | awk -v limit="$LIMIT" '$1 > limit && $2 != "total" { print }')
if [ -n "$OFFENDERS" ]; then
  echo "$OFFENDERS"
  echo "Split these files before adding more to them." >&2
  exit 1
fi

DEST="${SIMULATOR_ID:-}"
if [ -z "$DEST" ]; then
  DEST=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    for device in devices[runtime]:
        if device.get("isAvailable") and "iPhone" in device["name"]:
            print(device["udid"])
            raise SystemExit
')
fi
if [ -z "$DEST" ]; then
  echo "No iPhone simulator available." >&2
  exit 1
fi
echo "Simulator: $DEST"

echo "== Build =="
xcodebuild build -project revert.xcodeproj -scheme Revert \
  -destination "platform=iOS Simulator,id=$DEST" \
  -derivedDataPath .build-verify CODE_SIGNING_ALLOWED=NO | tail -3

echo "== Tests =="
xcodebuild test -project revert.xcodeproj -scheme RevertTests \
  -destination "platform=iOS Simulator,id=$DEST" \
  -derivedDataPath .build-verify CODE_SIGNING_ALLOWED=NO | tail -5

echo "== Lint (optional) =="
"$(dirname "$0")/lint.sh"

echo "verify: ok"
