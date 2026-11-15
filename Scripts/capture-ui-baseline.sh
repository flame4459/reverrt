#!/usr/bin/env bash
#
# Capture a repeatable baseline of the main Revert screens on a booted
# simulator. The PNGs are local-only (`.ui-baseline/` is gitignored); commit
# the manifest or a downscaled contact sheet if a review needs a permanent
# reference.
#
# Usage:
#   Scripts/capture-ui-baseline.sh [output-dir]
#
# Environment:
#   DEVICE     simulator UDID or "booted" (default: booted)
#   BUNDLE_ID  app bundle id (default: com.davidmolina.Revert)
#   SETTLE     seconds to wait after launch (default: 3)
#   LOCATION   simulator fix, "lat,lon" (default: 37.7749,-122.4194)
#
# The captures reflect the simulator's current SwiftData store. For a true
# first-run baseline, use a dedicated simulator or uninstall/reinstall the app
# before running this script.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEVICE="${DEVICE:-booted}"
BUNDLE_ID="${BUNDLE_ID:-com.davidmolina.Revert}"
SETTLE="${SETTLE:-3}"
LOCATION="${LOCATION:-37.7749,-122.4194}"
OUT="${1:-.ui-baseline/$(date +%Y%m%d-%H%M%S)}"

if ! xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" app >/dev/null 2>&1; then
    cat >&2 <<EOF
Revert is not installed on "$DEVICE".

Build and install it first, for example:
  xcodebuild build -project revert.xcodeproj -scheme Revert \\
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \\
    -derivedDataPath .build-phase0 CODE_SIGNING_ALLOWED=NO
  xcrun simctl install "$DEVICE" \\
    .build-phase0/Build/Products/Debug-iphonesimulator/Revert.app
EOF
    exit 1
fi

mkdir -p "$OUT"
APP="$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo unknown)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo unknown)"

# Freeze the status bar so image diffs are about the UI, not the clock, and
# give the app a fix so Routes/Plan show the GPS-ready state consistently.
xcrun simctl status_bar "$DEVICE" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true
if [[ -n "$LOCATION" ]]; then
    xcrun simctl location "$DEVICE" set "$LOCATION" >/dev/null 2>&1 || true
fi

cleanup() {
    xcrun simctl status_bar "$DEVICE" clear >/dev/null 2>&1 || true
    xcrun simctl location "$DEVICE" clear >/dev/null 2>&1 || true
}
trap cleanup EXIT

{
    printf 'captured_at\t%s\n' "$(date +%Y-%m-%dT%H:%M:%S%z)"
    printf 'device\t%s\n' "$DEVICE"
    printf 'bundle\t%s\n' "$BUNDLE_ID"
    printf 'version\t%s (%s)\n' "$VERSION" "$BUILD"
    printf 'settle_seconds\t%s\n' "$SETTLE"
    printf 'location\t%s\n' "$LOCATION"
} >"$OUT/manifest.txt"
: >"$OUT/manifest.tsv"

capture() {
    local name="$1"
    shift
    xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
    xcrun simctl launch "$DEVICE" "$BUNDLE_ID" "$@" >/dev/null
    sleep "$SETTLE"
    xcrun simctl io "$DEVICE" screenshot "$OUT/$name.png" >/dev/null 2>&1
    printf '%s\t%s\n' "$name" "$*" >>"$OUT/manifest.tsv"
    printf '  %s\n' "$name"
}

echo "Capturing Revert baseline to $OUT"
capture home -skipOnboarding -debugSeedRide -debugSeedLoops -debugGarageSeed
capture routes -skipOnboarding -debugTabRoutes
capture plan -skipOnboarding -debugPlan
capture cockpit-idle -skipOnboarding -debugTabRide
capture cockpit-recording -skipOnboarding -debugHud -debugRecord
capture history -skipOnboarding -debugTabHistory
capture garage -skipOnboarding -debugTabGarage
capture settings -skipOnboarding -debugSheetSettings
capture insights -skipOnboarding -debugSheetInsights
capture safety -skipOnboarding -debugSheetSafety
capture posters -skipOnboarding -debugSheetPosters
capture summary -skipOnboarding -debugSummary
capture onboarding -resetOnboarding

echo
echo "Done. $(wc -l <"$OUT/manifest.tsv" | tr -d ' ') screens in $OUT"
echo "Manifest: $OUT/manifest.tsv"
