#!/usr/bin/env bash
# Runs the optional formatter and linter when they are installed.
set -euo pipefail
cd "$(dirname "$0")/.."
if command -v swiftformat >/dev/null 2>&1; then
  swiftformat --lint .
else
  echo "swiftformat not installed; skipping"
fi
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint --strict
else
  echo "swiftlint not installed; skipping"
fi
