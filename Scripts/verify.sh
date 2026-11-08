#!/bin/bash
set -euo pipefail

# Local verification for RiderApp.
# Usage: ./Scripts/verify.sh ["iPhone 18 Pro"]
DEVICE="${1:-iPhone 18 Pro}"
PROJECT="Untitled Project.xcodeproj"
SCHEME="Untitled Project"
DERIVED=".build"
EXTRA_FLAGS="${EXTRA_SWIFT_FLAGS:-}"

echo "== Build =="
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="$EXTRA_FLAGS" \
  build

echo "== Tests =="
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="$EXTRA_FLAGS"
