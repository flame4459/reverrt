#!/usr/bin/env bash
#
# Run the Revert UI tests with a simulated location, so the planner can build
# a route and the live-ride test can record enough points to save.
#
# Usage:
#   Scripts/run-ui-tests.sh [xcodebuild test arguments...]
#
# Examples:
#   Scripts/run-ui-tests.sh -only-testing:RevertUITests/AccessibilityContractUITests
#   Scripts/run-ui-tests.sh -only-testing:RevertUITests/PulseShellUITests
#
# Environment:
#   DEVICE       simulator UDID or "booted" (default: booted)
#   DERIVED      derived data path (default: .build-phase0)
#   DESTINATION  xcodebuild destination
#                (default: platform=iOS Simulator,name=iPhone 17 Pro)
#   SCENARIO     simctl location scenario (default: "City Bicycle Ride")

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVICE="${DEVICE:-booted}"
DERIVED="${DERIVED:-.build-phase0}"
SCENARIO="${SCENARIO:-City Bicycle Ride}"

if [[ -z "${DESTINATION:-}" ]]; then
    if [[ "$DEVICE" == "booted" ]]; then
        UDID="$(xcrun simctl list devices booted -j 2>/dev/null \
            | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next((x["udid"] for r in d.values() for x in r if x.get("state") == "Booted"), ""))' \
            2>/dev/null || true)"
    else
        UDID="$DEVICE"
    fi
    if [[ -n "${UDID:-}" ]]; then
        DESTINATION="platform=iOS Simulator,id=$UDID"
    else
        DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro"
    fi
fi

cleanup() {
    xcrun simctl location "$DEVICE" clear >/dev/null 2>&1 || true
}
trap cleanup EXIT

# A route needs a fix and a recorded ride needs movement. The scenario loops
# while the suite runs; `clear` on exit leaves the simulator as we found it.
xcrun simctl location "$DEVICE" run "$SCENARIO" >/dev/null 2>&1 || {
    echo "warning: could not start location scenario '$SCENARIO'" >&2
}
sleep 2

xcodebuild test \
    -project revert.xcodeproj \
    -scheme RevertUITests \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" \
    -retry-tests-on-failure \
    "$@"
