#!/usr/bin/env bash
# Builds Pinfall for iOS on a Mac with Xcode installed.
# Usage:
#   ./build.sh                # debug build for a connected simulator/device
#   ./build.sh archive        # release archive (needs a Development Team set in Xcode)
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "archive" ]; then
  xcodebuild -project Pinfall.xcodeproj -scheme Pinfall -configuration Release \
    -destination 'generic/platform=iOS' archive -archivePath build/Pinfall.xcarchive
  echo "Archive ready: build/Pinfall.xcarchive (open it in Xcode to distribute)"
else
  xcodebuild -project Pinfall.xcodeproj -scheme Pinfall -configuration Debug \
    -destination 'generic/platform=iOS Simulator,name=iPhone 16' build
  echo "Build OK. Run it from Xcode, or: xcrun simctl install booted <path-to-app>"
fi
